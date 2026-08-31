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


## Federal vans are a paint-only atmosphere layer. The state adapter intentionally has no
## collision or gameplay side effects; raid progression remains owned by ProgressionTable.
func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.ACTIVE if _active \
			else TableVisualState.VisualState.DISABLED
	var mods: Array[StringName] = []
	if _active:
		mods.append(&"raid_phase")
		if _sweep > 0.001:
			mods.append(&"moving")
	return TableVisualState.state_token(state, mods)


func visual_token() -> Dictionary:
	return visual_state()


func _ambient(role: StringName, fallback: Color) -> Color:
	if Presentation != null and Presentation.city != null:
		var city_col := Presentation.city.material_for(role)
		if city_col.a > 0.0:
			return city_col
	if Presentation != null and Presentation.theme != null:
		var material := Presentation.theme.material_for(role)
		var fill: Variant = material.get("fill", fallback)
		if fill is Color:
			return fill as Color
	return fallback


func _semantic_color(role: StringName, fallback: Color) -> Color:
	if Presentation != null and Presentation.theme != null:
		var candidate := Presentation.theme.color(role)
		if candidate.a > 0.0:
			return candidate
	return fallback


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
	var ink := _ambient(&"ink_glass", Feel.COL_INK)
	var paper := _ambient(&"paper", Feel.COL_NEWSPRINT)
	var police := _semantic_color(&"police", paper)
	for i in range(VAN_AT.size()):
		var at: Vector2 = VAN_AT[i]
		# the two lights walk in opposite directions, so the block is never dark on one side
		var phase := (0.0 if Presentation.fx != null and Presentation.fx.reduced_flash \
				else _sweep / SWEEP_PERIOD * TAU) + (PI if i == 1 else 0.0)
		_draw_beam(at + Vector2(0.0, -VAN_SIZE.y * 0.5),
				sin(phase) * deg_to_rad(SWEEP_DEG), police)
		_draw_van(at, ink, paper, police)


func _draw_beam(from: Vector2, swing: float, police: Color = Feel.COL_NEWSPRINT) -> void:
	var dir := Vector2.UP.rotated(swing)
	var side := Vector2(-dir.y, dir.x)
	var tip := from + dir * BEAM_LENGTH
	draw_colored_polygon(PackedVector2Array([
		from - side * 12.0, from + side * 12.0,
		tip + side * 130.0, tip - side * 130.0,
	]), Color(police.r, police.g, police.b, 0.08))
	draw_colored_polygon(PackedVector2Array([
		from - side * 5.0, from + side * 5.0,
		tip + side * 42.0, tip - side * 42.0,
	]), Color(police.r, police.g, police.b, 0.08))
	draw_line(from, from + dir * 120.0,
			Color(police.r, police.g, police.b, 0.34), 6.0)
	draw_circle(from, 7.0, Color(police.r, police.g, police.b, 0.7))


func _draw_van(at: Vector2, ink: Color = Feel.COL_INK, paper: Color = Feel.COL_NEWSPRINT,
		police: Color = Feel.COL_NEWSPRINT) -> void:
	var body := ink.lightened(0.10)
	draw_rect(Rect2(at - VAN_SIZE * 0.5 - Vector2(4.0, 4.0), VAN_SIZE + Vector2(8.0, 8.0)), ink)
	draw_rect(Rect2(at - VAN_SIZE * 0.5, VAN_SIZE), body)
	draw_rect(Rect2(at - VAN_SIZE * 0.5, VAN_SIZE), paper.darkened(0.68), false, 3.0)
	# a slab of windscreen, a roof aerial and two wheels — an unmarked van in one glance
	var glass := Rect2(at + Vector2(-VAN_SIZE.x * 0.5 + 10.0, -VAN_SIZE.y * 0.5 + 9.0),
			Vector2(VAN_SIZE.x * 0.34, VAN_SIZE.y * 0.4))
	draw_rect(glass, ink.darkened(0.55))
	draw_line(glass.position + Vector2(5.0, 3.0), glass.end - Vector2(2.0, 3.0),
			Color(police.r, police.g, police.b, 0.42), 2.0)
	draw_line(at + Vector2(VAN_SIZE.x * 0.22, -VAN_SIZE.y * 0.5),
			at + Vector2(VAN_SIZE.x * 0.30, -VAN_SIZE.y * 0.5 - 34.0), paper.darkened(0.10), 3.0)
	draw_circle(at + Vector2(VAN_SIZE.x * 0.22, -VAN_SIZE.y * 0.5), 5.0, police)
	for x: float in [-VAN_SIZE.x * 0.28, VAN_SIZE.x * 0.28]:
		draw_circle(at + Vector2(x, VAN_SIZE.y * 0.5), 11.0, ink.darkened(0.25))
		draw_circle(at + Vector2(x, VAN_SIZE.y * 0.5), 5.0, paper.darkened(0.50))
	# The short bar survives grayscale as a roof silhouette, not a hue-only police signal.
	draw_line(at + Vector2(-20.0, -VAN_SIZE.y * 0.5 + 4.0),
			at + Vector2(18.0, -VAN_SIZE.y * 0.5 + 4.0), police, 3.0)
