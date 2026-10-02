class_name ViewFogOfWar
extends RefCounted
## Per-cell fog-of-war feed (render spec 5.7). Contract with the sim's vision layer (SimFogApi): `fog_bytes(pid)` is w * h bytes,
## 0 = shroud, 1 = fog (explored), 2 = visible, `fog_version(pid)` increments on change (<= 10 Hz).
## The bytes reach the GPU untouched (R8, sampled with texelFetch); all smoothing happens in shaders. Two textures ping-pong so
## the shaders cross-fade the previous and current state over 100 ms (`advance` drives `fow_blend`). The globals are declared by
## ViewGlobals.ensure(); this class only writes them. Presentation only: it never mutates the sim.

const STATE_SHROUD: int = 0
const STATE_FOG: int = 1
const STATE_VISIBLE: int = 2

const MODE_NONE: int = 0  ## rules.fog_mode 0: everything visible
const MODE_EXPLORED_VISIBLE: int = 1  ## explored terrain stays undimmed (fow_fog_dim = 0)
const MODE_SHROUD_FOG: int = 2  ## shroud + dimmed fog (default)

var cells_w: int = 0
var cells_h: int = 0
var update_interval: float = ViewConsts.FOG_UPDATE_S
var last_upload_us: int = 0
var uploads: int = 0
var mode: int = MODE_SHROUD_FOG
var enabled: bool = true
var local_pid: int = -1  ## pid whose bytes are shown; -1 = observer (all visible)
var last_version: int = -1
var rect: Vector4 = Vector4.ZERO  ## last published fow_rect (origin.x, origin.z, 1 / size.x, 1 / size.z)
var fog_dim: float = 1.0  ## last published fow_fog_dim

var _img: Image = null
var _tex: Array[ImageTexture] = []
var _cur: int = 0
var _blend: float = 1.0
var _visible_bytes: PackedByteArray = PackedByteArray()
var _origin_m: Vector2 = Vector2.ZERO
var _cell_m: float = ViewConsts.CELL_M


## Creates the two R8 textures (all shroud) and publishes fow_rect / fow_cells. `origin_m` is the world XZ of cell (0, 0).
func setup(w: int, h: int, origin_m: Vector2, cell_m: float) -> void:
	ViewGlobals.ensure()
	cells_w = w
	cells_h = h
	_origin_m = origin_m
	_cell_m = cell_m
	var zero: PackedByteArray = PackedByteArray()
	zero.resize(w * h)
	_visible_bytes = PackedByteArray()
	_visible_bytes.resize(w * h)
	_visible_bytes.fill(STATE_VISIBLE)
	_img = Image.create_from_data(w, h, false, Image.FORMAT_R8, zero)
	_tex = [ImageTexture.create_from_image(_img), ImageTexture.create_from_image(_img)]
	_cur = 0
	last_version = -1
	rect = Vector4(origin_m.x, origin_m.y, 1.0 / (float(w) * cell_m), 1.0 / (float(h) * cell_m))
	ViewGlobals.set_value(ViewGlobals.G_FOW_RECT, rect)
	ViewGlobals.set_value(ViewGlobals.G_FOW_CELLS, Vector2(float(w), float(h)))
	set_mode(mode)
	_publish()


## Uploads a new state grid: no conversion, the sim's bytes are the texture. The array is read-only for the view.
func submit(states: PackedByteArray) -> void:
	if _img == null or states.size() != cells_w * cells_h:
		return
	var t0: int = Time.get_ticks_usec()
	_cur = 1 - _cur
	_img.set_data(cells_w, cells_h, false, Image.FORMAT_R8, states)
	_tex[_cur].update(_img)
	_blend = 0.0
	_publish()
	last_upload_us = Time.get_ticks_usec() - t0
	uploads += 1


## Uploads api.fog_bytes(pid) iff api.fog_version(pid) changed since the last upload. True when an upload happened. Nothing is
## uploaded while fog is disabled (mode 0, observer): the all-visible texture stays.
func sync(api: SimFogApi, pid: int) -> bool:
	if not enabled or mode == MODE_NONE or api == null:
		return false
	var v: int = api.fog_version(pid)
	if v == last_version:
		return false
	var bytes: PackedByteArray = api.fog_bytes(pid)
	if bytes.size() != cells_w * cells_h:
		return false  # the default SimFogApi has no vision data: keep the current texture
	last_version = v
	submit(bytes)
	return true


## Convenience for ViewWorld: syncs the local player's bytes (observer / replay: local_pid -1 shows everything).
func sync_local(api: SimFogApi) -> bool:
	return sync(api, local_pid) if local_pid >= 0 else false


## Replays and observers: which pid's bytes are shown (-1 = observer, everything visible).
func set_local_player(pid: int) -> void:
	local_pid = pid
	last_version = -1
	if pid < 0:
		_show_all_visible()


## Per frame: drives the prev -> curr cross-fade so the 10 Hz data looks continuous.
func advance(dt: float) -> void:
	if _blend < 1.0:
		_blend = minf(1.0, _blend + dt / update_interval)
		ViewGlobals.set_value(ViewGlobals.G_FOW_BLEND, _blend)


## rules.fog_mode: 0 none (all-visible texture), 1 explored-stays-visible (fow_fog_dim = 0), 2 shroud + fog (fow_fog_dim = 1).
func set_mode(fog_mode: int) -> void:
	mode = clampi(fog_mode, MODE_NONE, MODE_SHROUD_FOG)
	fog_dim = 1.0 if mode == MODE_SHROUD_FOG else 0.0
	ViewGlobals.set_value(ViewGlobals.G_FOW_FOG_DIM, fog_dim)
	last_version = -1
	if mode == MODE_NONE or not enabled:
		_show_all_visible()


## false: all-visible texture (observer); true: the sim's bytes are shown again from the next sync.
func set_enabled(on: bool) -> void:
	enabled = on
	last_version = -1
	if not on or mode == MODE_NONE:
		_show_all_visible()


func current_texture() -> ImageTexture:
	return _tex[_cur]


## Bytes of the last upload (the Image the textures are refreshed from; the headless renderer keeps no texture data).
func current_bytes() -> PackedByteArray:
	return _img.get_data()


## Cross-fade progress 0..1 (test hook).
func blend() -> float:
	return _blend


## Both textures say "visible" at once (no cross-fade), the state of mode 0 and of observers.
func _show_all_visible() -> void:
	if _img == null:
		return
	_img.set_data(cells_w, cells_h, false, Image.FORMAT_R8, _visible_bytes)
	_tex[0].update(_img)
	_tex[1].update(_img)
	_blend = 1.0
	_publish()
	ViewGlobals.set_value(ViewGlobals.G_FOW_BLEND, 1.0)


func _publish() -> void:
	ViewGlobals.set_value(ViewGlobals.G_FOW_CURR, _tex[_cur])
	ViewGlobals.set_value(ViewGlobals.G_FOW_PREV, _tex[1 - _cur])
	ViewGlobals.set_value(ViewGlobals.G_FOW_BLEND, _blend)
