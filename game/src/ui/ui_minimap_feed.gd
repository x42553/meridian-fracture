class_name UiMinimapFeed
extends RefCounted
## SoA feed of the minimap (ui.md 4.2, 5.12): normalised dots with colour, size and class, remembered-structure
## ghosts and strategic-warning circles. Rebuilt from `UiSimPort.snapshot` every 2 ticks (10 Hz), which is fog
## honouring (own + allied + visible enemies + remembered structure ghosts), so the feed never reveals more than the
## viewer knows. Also bakes the placeholder fog texture used until the view supplies the fog material.

const C_INFANTRY: int = 0
const C_VEHICLE: int = 1
const C_AIR: int = 2
const C_NAVAL: int = 3
const C_STRUCTURE: int = 4
const C_SUPERWEAPON: int = 5
const C_NEUTRAL: int = 6
const PIP_NONE: int = 255

var dots_norm: PackedVector2Array = PackedVector2Array()
var dots_color: PackedColorArray = PackedColorArray()
var dots_size: PackedFloat32Array = PackedFloat32Array()
var dots_class: PackedByteArray = PackedByteArray()
var dots_own: PackedByteArray = PackedByteArray()  ## 1 = the viewer's own blip (+1 px, dark outline)
var dots_pip: PackedByteArray = PackedByteArray()
var ghost_norm: PackedVector2Array = PackedVector2Array()
var warn_norm: PackedVector2Array = PackedVector2Array()
var warn_radius_norm: PackedFloat32Array = PackedFloat32Array()
var map_w: int = 0
var map_h: int = 0
var revision: int = 0  ## incremented on every rebuild (the widget redraws when it changes)

var _snap: UiEntitySnapshot = UiEntitySnapshot.new()
var _warn: PackedInt32Array = PackedInt32Array()


static func size_of_class(cls: int) -> float:
	match cls:
		C_INFANTRY:
			return 2.0
		C_STRUCTURE:
			return 4.0
		C_SUPERWEAPON:
			return 8.0
		C_NEUTRAL:
			return 4.0
	return 3.0


## Rebuilds every array from the port. `caps` classifies units (null = `UiUnitCaps.shared_for(port)`).
func rebuild(port: UiSimPort, caps: UiUnitCaps = null) -> void:
	var c: UiUnitCaps = caps if caps != null else UiUnitCaps.shared_for(port)
	map_w = maxi(port.map_w(), 1)
	map_h = maxi(port.map_h(), 1)
	var cw: float = float(map_w) * 1024.0
	var ch: float = float(map_h) * 1024.0
	dots_norm.resize(0)
	dots_color.resize(0)
	dots_size.resize(0)
	dots_class.resize(0)
	dots_own.resize(0)
	dots_pip.resize(0)
	ghost_norm.resize(0)
	port.snapshot(_snap)
	var viewer: int = port.viewer_pid()
	var sw_eid: int = port.sw_launcher_eid()
	for i: int in _snap.count:
		var kind: int = _snap.kind_of(i)
		if kind == UiEntityRow.K_WRECK:
			continue
		var p := Vector2(float(_snap.xs[i]) / cw, float(_snap.ys[i]) / ch)
		var fl: int = _snap.flags[i]
		if (fl & UiEntityRow.F_GHOST) != 0:
			ghost_norm.append(p)
			continue
		var owner: int = _snap.owners[i]
		var cls: int = C_VEHICLE
		if kind == UiEntityRow.K_NEUTRAL_STRUCTURE:
			cls = C_NEUTRAL
		elif kind == UiEntityRow.K_STRUCTURE:
			cls = C_SUPERWEAPON if _snap.ids[i] == sw_eid and sw_eid > 0 else C_STRUCTURE
		else:
			var cp: int = c.caps_of(UiSimPort.KIND_UNIT, _snap.defs[i])
			if (cp & UiUnitCaps.CAP_AIR) != 0:
				cls = C_AIR
			elif (cp & UiUnitCaps.CAP_NAVAL) != 0:
				cls = C_NAVAL
			elif (cp & UiUnitCaps.CAP_INFANTRY) != 0:
				cls = C_INFANTRY
		var col: Color = UiPalette.TEXT_MUTE if owner < 0 else UiPalette.team(port.color_of(owner))
		var own: bool = owner >= 0 and owner == viewer
		dots_norm.append(p)
		dots_color.append(col)
		dots_size.append(size_of_class(cls) + (1.0 if own and cls != C_SUPERWEAPON else 0.0))
		dots_class.append(cls)
		dots_own.append(1 if own else 0)
		dots_pip.append(PIP_NONE)
	warn_norm.resize(0)
	warn_radius_norm.resize(0)
	var n: int = port.strategic_warnings(_warn)
	for i2: int in n:
		var b: int = i2 * UiSimPort.WARN_STRIDE
		warn_norm.append(Vector2(float(_warn[b + 4]) / cw, float(_warn[b + 5]) / ch))
		warn_radius_norm.append(float(_warn[b + 8]) / cw)
	revision += 1


func dot_count() -> int:
	return dots_norm.size()


## Placeholder fog texture (until the view's fog material exists): one texel per `stride` cells, black with alpha
## 0.78 in shroud, 0.42 in fog and 0 where visible. `img` is (re)created when the size differs; returns it.
static func bake_fog(port: UiSimPort, img: Image, max_side: int = 64) -> Image:
	var mw: int = maxi(port.map_w(), 1)
	var mh: int = maxi(port.map_h(), 1)
	var stride: int = maxi(1, ceili(float(maxi(mw, mh)) / float(max_side)))
	var w: int = ceili(float(mw) / float(stride))
	var h: int = ceili(float(mh) / float(stride))
	var out: Image = img
	if out == null or out.get_width() != w or out.get_height() != h:
		out = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		for x: int in w:
			var v: int = port.visibility(mini(x * stride + stride / 2, mw - 1), mini(y * stride + stride / 2, mh - 1))
			var a: float = 0.0
			if v == UiSimPort.Vis.SHROUD:
				a = 0.78
			elif v == UiSimPort.Vis.FOG:
				a = 0.42
			out.set_pixel(x, y, Color(0.0, 0.0, 0.02, a))
	return out
