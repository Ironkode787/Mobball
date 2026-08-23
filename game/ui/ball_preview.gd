class_name BallPreview
extends Control
## UI-neutral Roll Call preview of the same code-drawn face used by Ball.

var _design: Dictionary = BallDesign.anonymous()
var _pulse: float = 1.0


func _ready() -> void:
	custom_minimum_size = Vector2(72.0, 72.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_guy(guy: Dictionary) -> void:
	_design = BallDesign.for_guy(guy)
	queue_redraw()


func set_design(design: Dictionary) -> void:
	_design = BallDesign.anonymous() if design.is_empty() else design.duplicate()
	queue_redraw()


func design() -> Dictionary:
	return _design.duplicate()


func set_pulse(scale: float) -> void:
	_pulse = maxf(scale, 0.1)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.38
	if radius <= 0.0:
		radius = 28.0
	BallDesign.draw_ball(self, center, radius, _design, _pulse)
