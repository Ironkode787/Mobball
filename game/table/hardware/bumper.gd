class_name Bumper
extends StaticBody2D
## Pop bumper. Solid circle for the bounce plus a ring sensor exactly one ball-radius wider,
## so the kick fires the instant the surfaces touch instead of a frame later. Like a real
## skirt switch it also fires on a ball that has come to rest inside the ring — otherwise a
## ball can balance on the cap and stay there.

@export var id: StringName = &"bumper"
@export var value: int = Feel.BUMPER_VALUE

var _cooldown: float = 0.0
var _pulse: float = 0.0
var _inside: Array[Ball] = []


func _ready() -> void:
	collision_layer = Feel.LAYER_HARDWARE
	collision_mask = 0
	physics_material_override = Feel.make_material(Feel.RUBBER_FRICTION, 0.18)

	var body := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = Feel.BUMPER_RADIUS
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
	rc.radius = Feel.BUMPER_RADIUS + Feel.BALL_RADIUS
	rs.shape = rc
	ring.add_child(rs)
	add_child(ring)
	ring.body_entered.connect(_on_ball_entered)
	ring.body_exited.connect(_on_ball_exited)


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
	Events.switch_hit.emit(id, ball, Feel.BUMPER_IMPULSE)
	Events.scored.emit(id, value)


func _draw() -> void:
	var r := Feel.BUMPER_RADIUS * (1.0 + _pulse * 0.14)
	draw_circle(Vector2(0.0, 3.0), r, Color(0.0, 0.0, 0.0, 0.3))
	draw_circle(Vector2.ZERO, r, Feel.COL_INK)
	draw_arc(Vector2.ZERO, r - 4.0, 0.0, TAU, 40, Feel.COL_BRASS, 7.0)
	var cap := Feel.COL_FELT.lerp(Feel.COL_BRASS, 0.25 + _pulse * 0.6)
	draw_circle(Vector2.ZERO, r * 0.44, cap)
