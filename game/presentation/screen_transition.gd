class_name ScreenTransition
extends Control
## Full-screen handoff ritual. It hides synchronous screen-tree replacement behind a short
## cabinet/paper gesture and owns input only while that gesture is running.

const REVEAL_SECONDS := 0.16

var amount := 0.0:
	set(v):
		amount = clampf(v, 0.0, 1.0)
		queue_redraw()
var ritual: StringName = &"lights"
var caption := ""
var _tween: Tween = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 1000


## Same-frame handoff used by Main: the new screen is installed underneath a fully opaque
## layer before the renderer presents another frame, so game state remains synchronous.
func play_reveal(from_state: StringName, to_state: StringName) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	ritual = ritual_for(from_state, to_state)
	caption = caption_for(to_state)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	amount = 1.0
	if Presentation.fx.reduced_motion:
		call_deferred(&"_finish_reveal")
		return
	_tween = create_tween()
	_tween.tween_property(self, "amount", 0.0, REVEAL_SECONDS) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_finish_reveal)


func _finish_reveal() -> void:
	amount = 0.0
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func ritual_for(from_state: StringName, to_state: StringName) -> StringName:
	if from_state == &"night" and to_state == &"count":
		return &"receipt"
	if to_state == &"ledger" or from_state == &"ledger":
		return &"dossier"
	if from_state == &"attract" and to_state == &"roll_call":
		return &"shutter"
	return &"lights"


static func caption_for(state: StringName) -> String:
	match state:
		&"roll_call": return "ROLL CALL"
		&"night": return "THE NIGHT SHIFT"
		&"count": return "THE COUNT"
		&"ledger": return "THE LEDGER"
		_: return "KINGPIN"


func _draw() -> void:
	if amount <= 0.0:
		return
	var size := get_rect().size
	match ritual:
		&"shutter": _draw_shutter(size)
		&"receipt": _draw_receipt(size)
		&"dossier": _draw_dossier(size)
		_: _draw_lights(size)
	if amount > 0.58 and not caption.is_empty():
		var font := Presentation.theme.font_for(&"headline")
		var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 50).x
		var alpha := clampf((amount - 0.58) / 0.22, 0.0, 1.0)
		draw_string(font, Vector2((size.x - width) * 0.5, size.y * 0.53), caption,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 50, Color(Presentation.theme.newsprint, alpha))


func _draw_shutter(size: Vector2) -> void:
	var half := size.y * 0.5 * amount
	draw_rect(Rect2(0.0, 0.0, size.x, half), Presentation.theme.ink)
	draw_rect(Rect2(0.0, size.y - half, size.x, half), Presentation.theme.ink)
	var edge := Color(Presentation.theme.brass, amount)
	draw_rect(Rect2(0.0, half - 4.0, size.x, 4.0), edge)
	draw_rect(Rect2(0.0, size.y - half, size.x, 4.0), edge)


func _draw_lights(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Presentation.theme.ink, amount))
	var lit := Color(Presentation.theme.brass, amount)
	var dim := Color(Presentation.theme.brass.darkened(0.62), amount * 0.75)
	for i in 8:
		var x := size.x * (float(i) + 0.5) / 8.0
		var pulse := lit if (i % 2 == int(amount * 10.0) % 2) else dim
		draw_circle(Vector2(x, size.y * 0.12), 10.0 + 3.0 * amount, pulse)
		draw_circle(Vector2(x, size.y * 0.88), 10.0 + 3.0 * amount, pulse)


func _draw_receipt(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Presentation.theme.ink, amount * 0.92))
	var top := lerpf(-size.y, 0.0, amount)
	draw_rect(Rect2(0.0, top, size.x, size.y), Presentation.theme.newsprint)
	var line := Color(Presentation.theme.ink, 0.16 * amount)
	for y in range(90, int(size.y), 78):
		draw_line(Vector2(size.x * 0.13, top + y), Vector2(size.x * 0.87, top + y), line, 2.0)


func _draw_dossier(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Presentation.theme.ink, amount))
	var inset := lerpf(size.x * 0.48, size.x * 0.08, amount)
	var paper := Rect2(inset, size.y * 0.08, size.x - inset * 2.0, size.y * 0.84)
	draw_rect(paper, Color(Presentation.theme.newsprint, amount))
	draw_rect(paper, Color(Presentation.theme.brass, amount), false, 4.0)
	var pin := Vector2(paper.position.x + paper.size.x * 0.17, paper.position.y + 62.0)
	draw_line(pin, Vector2(paper.end.x - 76.0, paper.end.y - 90.0),
			Color(Presentation.theme.dirty, amount * 0.78), 5.0)
	draw_circle(pin, 13.0, Color(Presentation.theme.brass, amount))
