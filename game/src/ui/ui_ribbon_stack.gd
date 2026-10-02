class_name UiRibbonStack
extends VBoxContainer
## Ordered stack of `UiRibbon`s at the top centre (ui.md 5.13.1): at most `max_visible` (4, COMPACT 3), ordered DANGER >
## WARN > OK > INFO then newest first; a repeat of the same `rule_id` updates the ribbon in place instead of stacking;
## ribbons with a ttl expire by themselves. Mouse-transparent except over the ribbons.

signal ribbon_activated(rule_id: StringName)

var max_visible: int = UiMetrics.RIBBON_MAX
var _by_id: Dictionary = {}  ## rule_id -> UiRibbon


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", UiMetrics.RIBBON_GAP)
	alignment = BoxContainer.ALIGNMENT_BEGIN


## Adds or updates the ribbon of `rule_id`; returns it.
func post(rule_id: StringName, severity: int, title: String, subtitle: String, glyph: int, countdown_seconds: float = -1.0,
		charge: float = -1.0, tag: String = "", ttl_seconds: float = 0.0, sim_x: int = -1, sim_y: int = -1) -> UiRibbon:
	var r: UiRibbon = _by_id.get(rule_id) as UiRibbon
	if r == null or not is_instance_valid(r):
		r = UiRibbon.new()
		r.rule_id = rule_id
		r.activated.connect(func(id: StringName) -> void: ribbon_activated.emit(id))
		_by_id[rule_id] = r
		add_child(r)
		r.modulate.a = 0.0
		UiMotion.fade(self, r, 1.0, UiMotion.SLIDE_IN_S)
	r.severity = severity
	r.title = title
	r.subtitle = subtitle
	r.glyph = glyph
	r.countdown_seconds = countdown_seconds
	r.charge = charge
	r.tag = tag
	r.sim_x = sim_x
	r.sim_y = sim_y
	r.ttl_msec = int(ttl_seconds * 1000.0)
	if ttl_seconds > 0.0:
		r.created_msec = Time.get_ticks_msec()
	r.queue_redraw()
	_reorder()
	return r


func get_ribbon(rule_id: StringName) -> UiRibbon:
	var r: UiRibbon = _by_id.get(rule_id) as UiRibbon
	return r if r != null and is_instance_valid(r) else null


func has_ribbon(rule_id: StringName) -> bool:
	return get_ribbon(rule_id) != null


## Removes the ribbon (no-op when absent).
func clear(rule_id: StringName) -> void:
	var r: UiRibbon = get_ribbon(rule_id)
	_by_id.erase(rule_id)
	if r != null:
		remove_child(r)
		r.queue_free()
		_reorder()


func clear_all() -> void:
	for id: Variant in _by_id.keys():
		clear(id as StringName)


func count() -> int:
	return _by_id.size()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	for id: Variant in _by_id.keys():
		var r: UiRibbon = _by_id[id] as UiRibbon
		if r != null and r.ttl_msec > 0 and now - r.created_msec > r.ttl_msec:
			clear(id as StringName)


## Sorts by severity then age and hides everything beyond `max_visible`.
func _reorder() -> void:
	var list: Array[UiRibbon] = []
	for v: Variant in _by_id.values():
		var r: UiRibbon = v as UiRibbon
		if r != null and is_instance_valid(r):
			list.append(r)
	list.sort_custom(func(a: UiRibbon, b: UiRibbon) -> bool:
		if a.severity != b.severity:
			return a.severity > b.severity
		return a.created_msec > b.created_msec)
	for i: int in list.size():
		move_child(list[i], i)
		list[i].visible = i < max_visible
