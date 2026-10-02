class_name ViewFloatText
extends Node3D
## Floating world-space numbers (render spec 3.7 / 5.10): income "+$n" in gold at the refinery or wreck, repair "+n" in blue-white
## above the repaired structure. Label3D with billboard + fixed screen size + no depth test; each label rises RISE_M and fades over
## LIFE_S (1.2 s). Pool of POOL (24), the oldest label is recycled. Income of one source is aggregated over AGG_S (0.5 s).
## The font comes from ui (`ViewFloatText.font`), default ThemeDB.fallback_font. Presentation only.

const POOL: int = 24
const LIFE_S: float = 1.2
const RISE_M: float = 1.2
const AGG_S: float = 0.5
const GOLD: Color = Color(1.0, 0.85, 0.25)
const REPAIR: Color = Color(0.55, 0.85, 1.0)
const FONT_SIZE: int = 32
const INCOME_LIFT_M: float = 4.2  ## income numbers start above the refinery canopy (VQ2A: they were hidden behind the bay roof at 2 m)

## Set by the UI before the first popup (optional).
static var font: Font = null



static func release_statics() -> void:
	font = null

## World metres per screen pixel factor of a fixed-size Label3D (calibrated so the text is about 22 px tall at font_size 32).
var pixel_size: float = 0.0010

var active_count: int = 0  ## labels live last update

var _labels: Array[Label3D] = []
var _t0: PackedFloat32Array = PackedFloat32Array()
var _base: PackedVector3Array = PackedVector3Array()
var _col: PackedColorArray = PackedColorArray()
var _live: PackedByteArray = PackedByteArray()
var _next: int = 0
var _clock: float = 0.0
var _agg: Dictionary = {}  # key -> [amount, pos, first_time]
var total_popups: int = 0


func _ensure() -> void:
	if not _labels.is_empty():
		return
	for i: int in POOL:
		var l: Label3D = Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.fixed_size = true
		l.no_depth_test = true
		l.font_size = FONT_SIZE
		l.pixel_size = pixel_size
		l.outline_size = 8
		l.outline_modulate = Color(0.03, 0.03, 0.03, 0.9)
		l.render_priority = 11
		l.layers = ViewLayers.MASK_OVERLAYS
		l.visible = false
		if font != null:
			l.font = font
		add_child(l)
		_labels.append(l)
	_t0.resize(POOL)
	_base.resize(POOL)
	_col.resize(POOL)
	_live.resize(POOL)


func setup(_v: ViewWorld) -> void:
	_ensure()


## Shows `text` at `world_pos`; the oldest of the POOL labels is recycled when all are busy. `size_m` scales the font (1.0 = 32).
func popup(text: String, world_pos: Vector3, color: Color, size_m: float = 0.9) -> void:
	_ensure()
	var i: int = _next
	_next = (_next + 1) % POOL
	var l: Label3D = _labels[i]
	l.text = text
	l.font_size = int(float(FONT_SIZE) * clampf(size_m / 0.9, 0.5, 2.5))
	l.pixel_size = pixel_size
	l.modulate = color
	l.position = world_pos
	l.visible = true
	_t0[i] = _clock
	_base[i] = world_pos
	_col[i] = color
	_live[i] = 1
	total_popups += 1


## Income: aggregates amounts of one source (`key`, e.g. the refinery id) for AGG_S before the popup shows.
func add_income(key: int, amount: int, world_pos: Vector3) -> void:
	var rec: Array = _agg.get(key, [0, world_pos, _clock]) as Array
	rec[0] = (rec[0] as int) + amount
	rec[1] = world_pos
	_agg[key] = rec


func update(dt: float) -> void:
	if _labels.is_empty():
		return
	_clock += dt
	if not _agg.is_empty():
		var done: Array = []
		for k: Variant in _agg:
			var rec: Array = _agg[k] as Array
			if _clock - (rec[2] as float) >= AGG_S:
				popup("+$%d" % (rec[0] as int), (rec[1] as Vector3) + Vector3(0.0, INCOME_LIFT_M, 0.0), GOLD, clampf(0.95 + float(rec[0] as int) / 1500.0, 0.95, 1.4))
				done.append(k)
		for k2: Variant in done:
			_agg.erase(k2)
	var n: int = 0
	for i: int in POOL:
		if _live[i] == 0:
			continue
		var age: float = _clock - _t0[i]
		if age >= LIFE_S:
			_live[i] = 0
			_labels[i].visible = false
			continue
		var k3: float = age / LIFE_S
		var rise: float = RISE_M * (1.0 - (1.0 - k3) * (1.0 - k3))
		_labels[i].position = _base[i] + Vector3(0.0, rise, 0.0)
		var c: Color = _col[i]
		c.a = 1.0 - smoothstep(0.55, 1.0, k3)
		_labels[i].modulate = c
		_labels[i].outline_modulate = Color(0.03, 0.03, 0.03, 0.9 * c.a)
		n += 1
	active_count = n


func clear() -> void:
	for i: int in _labels.size():
		_live[i] = 0
		_labels[i].visible = false
	_agg.clear()
	active_count = 0
