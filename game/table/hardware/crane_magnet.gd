class_name CraneMagnet
extends Node2D
## The Docks crane (docs/02 §2 R5). A gantry trolley that runs the width of the yard, winds
## up, warns, and swings whatever it is holding out over the water.
##
## Same contract as the Captain's magnet by the drain (hardware/drain_magnet.gd) — a visible
## `TELEGRAPH` before every pull, because a grab with no tell is a coin flip, not difficulty
## — with three things that magnet does not need:
##
##   * **A gantry.** The trolley travels, so the pull comes from a place the player can watch
##     rather than from under the felt. Purely a transform on the drawing: a moving collider
##     in a room this size would be a wedge waiting to happen.
##   * **A zone.** It only ever reaches for a ball inside `zone`. A force field that could
##     yank a ball off the main playfield from inside a room it is not in would be a bug.
##   * **Self-driving by default.** The raid's magnet is scheduled by RaidMode; the crane is
##     table furniture and has no mode behind it yet, so it runs its own clock until the flow
##     lane takes it over with `self_driven = false`.

signal telegraph_started()
signal pulled(ball: Ball)

const PERIOD := 7.0
const TELEGRAPH := 1.2
const IMPULSE := 900.0
const TRAVEL_SPEED := 96.0
const HOOK_DROP := 46.0

@export var id: StringName = &"crane"

var active: bool = false
var self_driven: bool = true
## Where the hook swings the ball out to: the harbour, in table space.
var drop_point: Vector2 = Vector2.ZERO
## Only a ball inside this rect is in reach.
var zone: Rect2 = Rect2()
var rail_from: Vector2 = Vector2.ZERO
var rail_to: Vector2 = Vector2.ZERO

var _ball: Ball = null
var _phase: float = 0.0
var _telegraphing: bool = false
var _flash: float = 0.0
var _travel: float = 0.0
var _travel_dir: float = 1.0


func configure(p_id: StringName, from: Vector2, to: Vector2, p_zone: Rect2,
		p_drop: Vector2) -> void:
	id = p_id
	rail_from = from
	rail_to = to
	zone = p_zone
	drop_point = p_drop


func _ready() -> void:
	visible = false


func set_ball(b: Ball) -> void:
	_ball = b


func set_active(on: bool) -> void:
	if active == on:
		return
	active = on
	visible = on
	_phase = 0.0
	_telegraphing = false
	_flash = 0.0
	queue_redraw()


func is_telegraphing() -> bool:
	return _telegraphing


func time_to_pull() -> float:
	return PERIOD - _phase if active else -1.0


## Where the trolley is right now, in table space.
func trolley_position() -> Vector2:
	return rail_from.lerp(rail_to, _travel)


## Is there a ball the hook could actually reach?
func has_target(b: Ball = null) -> bool:
	var target := b if b != null else _ball
	if target == null or not is_instance_valid(target):
		return false
	if BallHold.is_held(target):
		return false                  # already riding a ramp: not the crane's to take
	return zone.has_point(target.global_position)


func pull(b: Ball = null) -> bool:
	var target := b if b != null else _ball
	if target == null or not has_target(target):
		return false
	var dir := drop_point - target.global_position
	if dir.length() < 1.0:
		return false
	target.kick(dir.normalized() * IMPULSE)
	AudioDirector.play(&"crane_pull")
	_flash = 1.0
	queue_redraw()
	pulled.emit(target)
	return true


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		queue_redraw()
	if not active:
		return
	_run_gantry(delta)
	_phase += delta
	if not _telegraphing and _phase >= PERIOD - TELEGRAPH:
		_telegraphing = true
		AudioDirector.play(&"crane_telegraph")
		telegraph_started.emit()
	if _phase < PERIOD:
		if _telegraphing:
			queue_redraw()
		return
	_phase = 0.0
	_telegraphing = false
	if self_driven:
		pull()
	queue_redraw()


## The trolley parks over the ball while it winds up and patrols when it has nothing to do —
## the telegraph is *where* it is as much as how bright it is.
func _run_gantry(delta: float) -> void:
	var span := rail_from.distance_to(rail_to)
	if span < 1.0:
		return
	var want := -1.0
	if has_target():
		var along := (_ball.global_position - rail_from).dot((rail_to - rail_from) / span)
		want = clampf(along / span, 0.0, 1.0)
	if want >= 0.0:
		var step := TRAVEL_SPEED * delta / span
		_travel = move_toward(_travel, want, step * 2.0)
	else:
		_travel += _travel_dir * TRAVEL_SPEED * delta / span
		if _travel >= 1.0:
			_travel = 1.0
			_travel_dir = -1.0
		elif _travel <= 0.0:
			_travel = 0.0
			_travel_dir = 1.0
	queue_redraw()


## The crane is yard furniture, not mode hardware: while it is built it is running. What the
## flow lane takes over later is `self_driven` — who decides *when* the hook drops.
func set_hardware_active(p_active: bool) -> void:
	set_active(p_active)


func is_hardware_active() -> bool:
	return active


## Draw-edge translation only. The crane's clock and reach remain owned by the existing
## physics process; a target/telegraph is represented as a state mark, never as a new force.
func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.IDLE
	var mods: Array[StringName] = []
	if not active:
		state = TableVisualState.VisualState.DISABLED
	elif _telegraphing:
		state = TableVisualState.VisualState.DANGER
		mods.append(&"telegraph")
	elif _flash > 0.02:
		state = TableVisualState.VisualState.COMPLETED
		mods.append(&"pulse")
	elif has_target():
		state = TableVisualState.VisualState.ARMED
	mods.append(&"moving" if _travel > 0.001 and _travel < 0.999 else &"parked")
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


func _hatch(rect: Rect2, color: Color, spacing: float = 14.0) -> void:
	var x := rect.position.x - rect.size.y
	while x < rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x + rect.size.y, rect.end.y), color, 2.0)
		x += spacing


func _draw_state_cue(center: Vector2, radius: float, token: Dictionary, color: Color) -> void:
	var mark := String(token["mark"])
	if mark == "telegraph_hatch" or mark == "hazard_hatch":
		draw_arc(center, radius, 0.0, TAU, 20, color, 3.0)
		_hatch(Rect2(center - Vector2(radius * 0.7, radius * 0.7), Vector2(radius * 1.4, radius * 1.4)),
				Color(color.r, color.g, color.b, 0.65), 8.0)
	elif mark == "check_stamp":
		draw_rect(Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)), color, false, 3.0)
		draw_line(center + Vector2(-radius * 0.5, 0.0), center + Vector2(-radius * 0.08, radius * 0.4), color, 3.0)
		draw_line(center + Vector2(-radius * 0.08, radius * 0.4), center + Vector2(radius * 0.56, -radius * 0.5), color, 3.0)
	elif mark == "invitation_pin":
		draw_circle(center, radius * 0.4, color)
		draw_line(center + Vector2(0.0, radius * 0.35), center + Vector2(0.0, radius), color, 3.0)
	else:
		draw_arc(center, radius, 0.0, TAU, 20, color, 3.0)


func _draw() -> void:
	if not active:
		return
	var token := visual_token()
	var state := String(token["state"])
	var reduced_flash := Presentation.fx != null and Presentation.fx.reduced_flash
	var warn := clampf((_phase - (PERIOD - TELEGRAPH)) / TELEGRAPH, 0.0, 1.0) if _telegraphing else 0.0
	if reduced_flash:
		warn = 0.28 if _telegraphing else 0.0
	var glow := maxf(warn, _flash * (0.25 if reduced_flash else 1.0))
	var ink := _ambient(&"ink_glass", Feel.COL_INK)
	var brass := _ambient(&"brass", Feel.COL_BRASS)
	var paper := _ambient(&"paper", Feel.COL_NEWSPRINT)
	var hazard := _semantic_color(&"dirty", Feel.COL_DIRTY)
	var rail := brass.darkened(0.55)
	# The doubled rail and end posts make the gantry legible as furniture, not a new wall.
	draw_line(rail_from, rail_to, ink, 18.0)
	draw_line(rail_from, rail_to, rail, 9.0)
	for endpoint: Vector2 in [rail_from, rail_to]:
		draw_line(endpoint, endpoint + Vector2(0.0, 54.0), ink, 10.0)
		draw_line(endpoint, endpoint + Vector2(0.0, 54.0), rail, 5.0)
	var trolley := trolley_position()
	var trolley_fill := brass.lerp(paper, glow * 0.35)
	if state == "danger":
		trolley_fill = hazard.lerp(paper, glow * 0.30)
	draw_rect(Rect2(trolley - Vector2(22.0, 13.0), Vector2(44.0, 26.0)), ink)
	draw_rect(Rect2(trolley - Vector2(18.0, 10.0), Vector2(36.0, 20.0)), trolley_fill)
	draw_line(trolley + Vector2(-13.0, -5.0), trolley + Vector2(13.0, -5.0), paper, 2.0)
	# the hook, lowered as it winds up
	var hook := trolley + Vector2(0.0, HOOK_DROP * (0.35 + glow * 0.65))
	draw_line(trolley, hook, rail.lightened(0.2), 3.0)
	var hook_col := brass.lerp(hazard, glow)
	draw_arc(hook, 10.0, 0.0, TAU, 14, hook_col, 4.0)
	if state == "armed":
		_draw_state_cue(trolley + Vector2(0.0, -28.0), 8.0, token, brass)
	if glow <= 0.0:
		return
	var col := Color(hazard.r, hazard.g, hazard.b,
			0.16 + glow * (0.58 if not reduced_flash else 0.24))
	for i in range(3):
		draw_arc(hook, 22.0 + float(i) * 20.0 + glow * 22.0, 0.0, TAU, 24, col, 4.0 - float(i))
	draw_line(hook, drop_point, Color(col.r, col.g, col.b, col.a * 0.5), 3.0)
	_draw_state_cue(hook + Vector2(0.0, 30.0), 11.0, token, hazard)
