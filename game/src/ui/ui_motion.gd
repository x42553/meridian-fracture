class_name UiMotion
extends RefCounted
## Durations and easings of the design system (ui.md 4.6.5, art 5.12.4). Every duration is 0 while
## `reduce_motion` is set, and `reduce_flash` replaces pulses by steady fills. Tweens must come from in-tree nodes
## (a tween created outside the tree does nothing, P24), so every helper takes the node that owns it.

const HOVER_S: float = 0.09
const PRESS_S: float = 0.06
const SLIDE_IN_S: float = 0.18
const SLIDE_OUT_S: float = 0.25
const SLIDE_PX: float = 24.0
const SCREEN_OUT_S: float = 0.18
const SCREEN_IN_S: float = 0.22
const TOAST_IN_S: float = 0.15
const TOAST_HOLD_S: float = 4.0
const TOAST_OUT_S: float = 0.3
const TICKER_S: float = 0.3
## Alert pulse (READY card, DANGER ribbon, low power): 1 Hz; nothing animates faster than 2 Hz (photosensitivity, <= 3 Hz always).
const PULSE_HZ: float = 1.0
const MAX_HZ: float = 2.0

## `access/reduce_motion`: all durations 0, no sweep, no scanlines, static badges.
static var reduce_motion: bool = false
## `access/reduce_flash`: pulses become steady fills.
static var reduce_flash: bool = false


## `seconds`, or 0 under reduce-motion.
static func dur(seconds: float) -> float:
	return 0.0 if reduce_motion else seconds


## Pulse value 0..1 at time `t_s` (1 Hz sine); a steady 1.0 under reduce-motion / reduce-flash.
static func pulse(t_s: float, hz: float = PULSE_HZ) -> float:
	if reduce_motion or reduce_flash:
		return 1.0
	return 0.5 + 0.5 * sin(TAU * minf(hz, MAX_HZ) * t_s)


## Tween that sets `prop` of `obj` to `to` in `seconds` (cubic ease-out by default); when the duration is 0 it
## assigns immediately and returns null. `owner` supplies the tween (must be in the tree).
static func tween_prop(owner: Node, obj: Object, prop: NodePath, to: Variant, seconds: float, trans: int = Tween.TRANS_CUBIC, ease_type: int = Tween.EASE_OUT) -> Tween:
	var d: float = dur(seconds)
	if d <= 0.0 or not owner.is_inside_tree():
		obj.set_indexed(prop, to)
		return null
	var tw: Tween = owner.create_tween()
	tw.tween_property(obj, prop, to, d).set_trans(trans).set_ease(ease_type)
	return tw


## Fade a canvas item's alpha (`modulate:a`).
static func fade(owner: Node, item: CanvasItem, to_alpha: float, seconds: float) -> Tween:
	return tween_prop(owner, item, ^"modulate:a", to_alpha, seconds)


## Slide a control in from `SLIDE_PX` px (default from above) while fading in (panel / ribbon / toast entry).
static func slide_in(owner: Node, ctrl: Control, from: Vector2 = Vector2(0.0, -SLIDE_PX), seconds: float = SLIDE_IN_S) -> Tween:
	var target: Vector2 = ctrl.position
	if dur(seconds) <= 0.0 or not owner.is_inside_tree():
		ctrl.modulate.a = 1.0
		return null
	ctrl.position = target + from
	ctrl.modulate.a = 0.0
	var tw: Tween = owner.create_tween().set_parallel(true)
	tw.tween_property(ctrl, "position", target, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ctrl, "modulate:a", 1.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw


## Slide out (`SLIDE_OUT_S`, ease-in) and fade; the returned tween's `finished` is the place to free the node.
static func slide_out(owner: Node, ctrl: Control, to: Vector2 = Vector2(0.0, -SLIDE_PX), seconds: float = SLIDE_OUT_S) -> Tween:
	if dur(seconds) <= 0.0 or not owner.is_inside_tree():
		ctrl.modulate.a = 0.0
		return null
	var tw: Tween = owner.create_tween().set_parallel(true)
	tw.tween_property(ctrl, "position", ctrl.position + to, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(ctrl, "modulate:a", 0.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	return tw
