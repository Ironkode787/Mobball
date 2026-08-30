class_name FederalVans
extends Node2D
## THE WIRETAP — phase 2 of the federal raid (docs/05 §9, specs/m3-fall-rise.md sub-wave B).
## Two unmarked vans parked in the bottom corners of the field with their spotlights walking
## up the block.
##
## **Paint, and only paint.** There is no collider in this file and there never will be one:
## the machine's geometry may not change because a meter upstairs went red. The federal raid
## is allowed to make the table *feel* different — a denser tint, a second magnet, four cops
## — but every one of those is hardware the table already had. A pair of vans that could
## deflect a ball would be a new wall the player never bought and cannot see coming.
##
## Drawn on the idle frame rather than the physics tick: a sweeping light is animation, and
## nothing in the game may read its position.

## The corners they park in. Below the outlane guides and outside the bats' arc, which on
## this table is the apron — where a stakeout would actually sit.
const VAN_AT: Array = [Vector2(100.0, 1712.0), Vector2(880.0, 1712.0)]
const VAN_SIZE := Vector2(110.0, 52.0)
## Seconds for one full pass of a spotlight, and how far off straight-up it swings.
const SWEEP_PERIOD := 5.5
const SWEEP_DEG := 26.0
const BEAM_LENGTH := 900.0

var _active: bool = false
var _sweep: float = 0.0


func _ready() -> void:
	visible = false
	set_process(false)


func set_active(on: bool) -> void:
	if _active == on:
		return
	_active = on
	visible = on
	_sweep = 0.0
	set_process(on)
	queue_redraw()


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if Presentation.fx != null and Presentation.fx.reduced_flash:
		if _sweep != 0.0:
			_sweep = 0.0
			queue_redraw()
		return
	_sweep = fmod(_sweep + delta, SWEEP_PERIOD)
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	for i in range(VAN_AT.size()):
		var at: Vector2 = VAN_AT[i]
		# the two lights walk in opposite directions, so the block is never dark on one side
		var phase := (0.0 if Presentation.fx != null and Presentation.fx.reduced_flash \
				else _sweep / SWEEP_PERIOD * TAU) + (PI if i == 1 else 0.0)
		_draw_beam(at + Vector2(0.0, -VAN_SIZE.y * 0.5), sin(phase) * deg_to_rad(SWEEP_DEG))
		_draw_van(at)


func _draw_beam(from: Vector2, swing: float) -> void:
	var dir := Vector2.UP.rotated(swing)
	var side := Vector2(-dir.y, dir.x)
	var tip := from + dir * BEAM_LENGTH
	draw_colored_polygon(PackedVector2Array([
		from - side * 12.0, from + side * 12.0,
		tip + side * 130.0, tip - side * 130.0,
	]), Color(Feel.COL_NEWSPRINT.r, Feel.COL_NEWSPRINT.g, Feel.COL_NEWSPRINT.b, 0.09))
	draw_line(from, from + dir * 120.0,
			Color(Feel.COL_NEWSPRINT.r, Feel.COL_NEWSPRINT.g, Feel.COL_NEWSPRINT.b, 0.24), 6.0)


func _draw_van(at: Vector2) -> void:
	var body := Feel.COL_INK.lightened(0.06)
	draw_rect(Rect2(at - VAN_SIZE * 0.5, VAN_SIZE), body)
	draw_rect(Rect2(at - VAN_SIZE * 0.5, VAN_SIZE), Feel.COL_INK.darkened(0.4), false, 3.0)
	# a slab of windscreen, a roof aerial and two wheels — an unmarked van in one glance
	draw_rect(Rect2(at + Vector2(-VAN_SIZE.x * 0.5 + 10.0, -VAN_SIZE.y * 0.5 + 9.0),
			Vector2(VAN_SIZE.x * 0.34, VAN_SIZE.y * 0.4)), Feel.COL_INK.darkened(0.55))
	draw_line(at + Vector2(VAN_SIZE.x * 0.22, -VAN_SIZE.y * 0.5),
			at + Vector2(VAN_SIZE.x * 0.30, -VAN_SIZE.y * 0.5 - 34.0),
			Feel.COL_INK.lightened(0.22), 3.0)
	for x: float in [-VAN_SIZE.x * 0.28, VAN_SIZE.x * 0.28]:
		draw_circle(at + Vector2(x, VAN_SIZE.y * 0.5), 11.0, Feel.COL_INK.darkened(0.25))
