class_name Bumper
extends StaticBody2D
## Pop bumper. Solid circle for the bounce plus a ring sensor exactly one ball-radius wider,
## so the kick fires the instant the surfaces touch instead of a frame later. Like a real
## skirt switch it also fires on a ball that has come to rest inside the ring — otherwise a
## ball can balance on the cap and stay there.

@export var id: StringName = &"bumper"
@export var value: int = Feel.BUMPER_VALUE
## Economy group this can pays into (specs/ledger-data.md `value_mult` targets).
@export var group: StringName = &"bumpers"
## The progression table uses three mismatched cans: one broad anchor and two quicker
## satellites. Authored geometry is scaled directly so the skirt and visible lid agree.
@export var size_scale: float = 1.0

var _present: bool = true
var _cooldown: float = 0.0
var _pulse: float = 0.0
var _inside: Array[Ball] = []
var _ring: Area2D = null


func _ready() -> void:
	collision_layer = Feel.LAYER_HARDWARE
	collision_mask = 0
	physics_material_override = Feel.make_material(Feel.RUBBER_FRICTION, 0.18)

	var body := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = Feel.BUMPER_RADIUS * size_scale
	body.shape = circle
	body.name = "Body"
	add_child(body)

	var ring := Area2D.new()
	ring.name = "Ring"
	ring.collision_layer = Feel.LAYER_ZONES
	ring.collision_mask = Feel.LAYER_BALL
	ring.monitorable = false
	var rs := CollisionShape2D.new()
	var rc := CircleShape2D.new()
	rc.radius = Feel.BUMPER_RADIUS * size_scale + Feel.BALL_RADIUS
	rs.shape = rc
	ring.add_child(rs)
	add_child(ring)
	ring.body_entered.connect(_on_ball_entered)
	ring.body_exited.connect(_on_ball_exited)
	_ring = ring
	_apply_collision()


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 6.0, 0.0)
		queue_redraw()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	# a real pop bumper's skirt fires on contact, not on approach: a ball that comes to rest
	# on the cap has to be thrown off again or it sits there for the rest of the night
	if _inside.is_empty():
		return
	for i in range(_inside.size() - 1, -1, -1):
		if not is_instance_valid(_inside[i]):
			_inside.remove_at(i)
	if _cooldown > 0.0:
		return
	for b in _inside:
		if b.speed() < Feel.HARDWARE_STALL_SPEED:
			_kick(b)
			return


func _on_ball_exited(body: Node2D) -> void:
	if body is Ball:
		_inside.erase(body as Ball)


func _on_ball_entered(body: Node2D) -> void:
	if not (body is Ball):
		return
	_inside.append(body as Ball)
	if _cooldown > 0.0:
		return
	_kick(body as Ball)


func _kick(ball: Ball) -> void:
	_cooldown = Feel.BUMPER_COOLDOWN
	var away := (ball.global_position - global_position)
	if away.length() < 0.001:
		away = Vector2.UP
	away = away.normalized()
	ball.kick(away * Feel.BUMPER_IMPULSE)
	_pulse = 1.0
	queue_redraw()
	AudioDirector.play(&"bumper_hit")
	TableScore.earn(group, float(value), id, ball, Feel.BUMPER_IMPULSE)


## A can that has not been bought yet is not on the table at all (progression_table.gd).
func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_inside.clear()
	_apply_collision()


func _apply_collision() -> void:
	collision_layer = Feel.LAYER_HARDWARE if _present else 0
	if _ring != null:
		_ring.collision_layer = Feel.LAYER_ZONES if _present else 0
		_ring.collision_mask = Feel.LAYER_BALL if _present else 0


func _draw() -> void:
	var r := Feel.BUMPER_RADIUS * size_scale * (1.0 + _pulse * 0.14)
	# A battered trash-can lid, not a generic pinball disc. The nested steel ribs make the
	# pulse read like the lid physically jumping when the skirt fires.
	draw_circle(Vector2(0.0, 7.0), r + 4.0, Color(0.0, 0.0, 0.0, 0.38))
	if _pulse > 0.0:
		draw_circle(Vector2.ZERO, r + 15.0,
				Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g, Feel.COL_BRASS.b, _pulse * 0.12))
	draw_circle(Vector2.ZERO, r, Feel.COL_INK.lightened(0.05))
	draw_arc(Vector2.ZERO, r - 3.0, 0.0, TAU, 40,
			Feel.COL_BRASS.lerp(Feel.COL_NEWSPRINT, _pulse * 0.62), 7.0)
	var steel := Feel.COL_NEWSPRINT.darkened(0.62).lerp(Feel.COL_BRASS, 0.20 + _pulse * 0.42)
	draw_circle(Vector2.ZERO, r * 0.68, steel.darkened(0.26))
	draw_arc(Vector2.ZERO, r * 0.62, 0.0, TAU, 32, steel, 4.0)
	draw_arc(Vector2.ZERO, r * 0.43, 0.0, TAU, 28, steel.darkened(0.12), 3.0)
	draw_circle(Vector2(-r * 0.12, -r * 0.10), r * 0.25, steel.darkened(0.18))
	# Each can has a different old dent, so three bought bumpers feel like three objects.
	var dent_sign := -1.0 if String(id).ends_with("2") else 1.0
	draw_arc(Vector2(dent_sign * r * 0.22, r * 0.08), r * 0.21,
			0.2, PI * 1.18, 10, Feel.COL_INK.lightened(0.17), 3.0)
	draw_line(Vector2(-r * 0.22, r * 0.35), Vector2(r * 0.30, r * 0.28),
			Color(Feel.COL_NEWSPRINT.r, Feel.COL_NEWSPRINT.g,
			Feel.COL_NEWSPRINT.b, 0.13), 2.0)
