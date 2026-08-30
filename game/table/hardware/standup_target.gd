class_name StandupTarget
extends StaticBody2D
## A standup: a payphone on The Wire, a cop during a raid, the beat cop's donut shop. It
## never leaves the playfield — it lights instead of dropping — so the geometry a player
## learns stays put. Whether a hit pays, and how much, is the owner's business: this only
## reports the strike.

signal struck(target: StandupTarget, ball: Ball)

const COOLDOWN := 0.22
## A standup is a capsule, and a capsule has two rounded caps. Top-down gravity gives the top
## of a cap a perfect balance point: a seeded soak found a ball asleep on the end of a
## Commission chair for 3.3 s and still going, and the M1 table's own header records the same
## thing happening on a payphone for seventy seconds. The coils hunt for that eventually
## (ProgressionTable.BALL_SEARCH_DELAY), but the piece the ball is asleep on can do better —
## so a standup pops it loose itself, which is the rule bumpers, slings and the Commission's
## vehicles already keep (Feel.HARDWARE_STALL_SPEED).
const STALL_IMPULSE := 560.0
const STALL_COOLDOWN := 0.6

@export var id: StringName = &"standup"

var marked: bool = false            ## bank bookkeeping: already collected this round
var length: float = 76.0
var thickness: float = 18.0
var facing: Vector2 = Vector2.LEFT

var _present: bool = true
var _face: Area2D = null
var _ring: Area2D = null
var _cooldown: float = 0.0
var _stall_cool: float = 0.0
var _pulse: float = 0.0
var _inside: Array[Ball] = []


func configure(p_id: StringName, center: Vector2, p_facing: Vector2, p_length: float = 76.0) -> void:
	id = p_id
	position = center
	facing = p_facing.normalized()
	length = p_length
	rotation = facing.angle() - PI * 0.5


func _ready() -> void:
	collision_layer = Feel.LAYER_HARDWARE
	collision_mask = 0
	physics_material_override = Feel.make_material(Feel.RUBBER_FRICTION, 0.30)

	var shape := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = thickness * 0.5
	cap.height = length + thickness
	shape.shape = cap
	shape.rotation = PI * 0.5
	shape.name = "Body"
	add_child(shape)

	_face = Area2D.new()
	_face.name = "Face"
	_face.collision_layer = Feel.LAYER_ZONES
	_face.collision_mask = Feel.LAYER_BALL
	_face.monitorable = false
	var fs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(length, Feel.BALL_RADIUS * 0.8)
	fs.shape = rect
	fs.position = Vector2(0.0, thickness * 0.5 + Feel.BALL_RADIUS * 0.4)
	_face.add_child(fs)
	add_child(_face)
	_face.body_entered.connect(_on_face_entered)

	_ring = Area2D.new()
	_ring.name = "Ring"
	_ring.collision_layer = Feel.LAYER_ZONES
	_ring.collision_mask = Feel.LAYER_BALL
	_ring.monitorable = false
	var rs := CollisionShape2D.new()
	var ring := CapsuleShape2D.new()
	ring.radius = thickness * 0.5 + Feel.BALL_RADIUS
	ring.height = length + thickness + Feel.BALL_RADIUS * 2.0
	rs.shape = ring
	rs.rotation = PI * 0.5
	_ring.add_child(rs)
	add_child(_ring)
	_ring.body_entered.connect(func(body: Node2D) -> void:
		if body is Ball and not _inside.has(body):
			_inside.append(body as Ball))
	_ring.body_exited.connect(func(body: Node2D) -> void:
		if body is Ball:
			_inside.erase(body as Ball))
	_apply_collision()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_stall_cool = maxf(_stall_cool - delta, 0.0)
	_pop_stalled()


## A ball asleep on this target — on a cap, or leaned against a flank — gets a shove off it,
## off the side it is actually resting on. The normal is read from `rotation`, not from
## `facing`: callers rake these by adding to `rotation` after `configure`, so the stored
## facing is the square one and only the live transform knows which way the bar is really lying.
func _pop_stalled() -> void:
	if not _present or _stall_cool > 0.0 or _inside.is_empty():
		return
	for i in range(_inside.size() - 1, -1, -1):
		if not is_instance_valid(_inside[i]):
			_inside.remove_at(i)
	for b in _inside:
		if BallHold.is_held(b) or b.speed() >= Feel.HARDWARE_STALL_SPEED:
			continue
		_stall_cool = STALL_COOLDOWN
		var away := b.global_position - global_position
		var normal := Vector2(0.0, 1.0).rotated(rotation)
		var side := 1.0 if away.dot(normal) >= 0.0 else -1.0
		var mixed := normal * side * 1.3 + away.normalized() * 0.7
		b.kick((mixed.normalized() if mixed.length() > 0.001 else Vector2.UP) * STALL_IMPULSE)
		return


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 5.0, 0.0)
		queue_redraw()


func _on_face_entered(body: Node2D) -> void:
	if not (body is Ball) or not _present or _cooldown > 0.0:
		return
	_cooldown = COOLDOWN
	_pulse = 1.0
	queue_redraw()
	struck.emit(self, body as Ball)


func set_marked(value: bool) -> void:
	if marked == value:
		return
	marked = value
	queue_redraw()


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_inside.clear()
	_apply_collision()


func _apply_collision() -> void:
	collision_layer = Feel.LAYER_HARDWARE if _present else 0
	for area: Area2D in [_face, _ring]:
		if area == null:
			continue
		area.collision_layer = Feel.LAYER_ZONES if _present else 0
		area.collision_mask = Feel.LAYER_BALL if _present else 0


func _draw() -> void:
	var half := length * 0.5
	var face := Feel.COL_BRASS if marked else Feel.COL_BRASS.darkened(0.55)
	face = face.lerp(Feel.COL_NEWSPRINT, _pulse * 0.8)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), Feel.COL_INK, thickness + 6.0)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), face, thickness)
	var sid := String(id)
	if sid.begins_with("wire_"):
		# Three payphones, complete with receiver hooks, instead of three anonymous bars.
		var booth := Rect2(Vector2(-half * 0.64, -54.0), Vector2(half * 1.28, 51.0))
		var phone_art := Presentation.art.resolve(&"prop.payphone_bank", null, false)
		if phone_art != null:
			draw_texture_rect(phone_art, booth, false, Color(1.0, 1.0, 1.0, 0.92))
		else:
			draw_rect(booth, Feel.COL_INK.lightened(0.06))
		draw_rect(booth, face.darkened(0.15), false, 3.0)
		draw_arc(Vector2(0.0, -16.0), 9.0, 0.15, PI - 0.15, 10, face, 4.0)
		draw_line(Vector2(-10.0, -15.0), Vector2(-14.0, -8.0), face, 4.0)
		draw_line(Vector2(10.0, -15.0), Vector2(14.0, -8.0), face, 4.0)
	elif sid == "bribe_target":
		# An envelope tucked under the donut-shop counter.
		var note := Rect2(Vector2(-22.0, -27.0), Vector2(44.0, 24.0))
		draw_rect(note, Feel.COL_NEWSPRINT.darkened(0.12))
		draw_line(note.position, note.get_center() + Vector2(0.0, 4.0), face, 2.0)
		draw_line(Vector2(note.end.x, note.position.y), note.get_center() + Vector2(0.0, 4.0),
				face, 2.0)
	elif sid.begins_with("cop_") or sid.begins_with("boss_goon_"):
		# Hat-and-shoulders target: enough character to read at speed, still a clean face.
		var body_col := Feel.COL_INK.lightened(0.16)
		draw_circle(Vector2(0.0, -19.0), 9.0, body_col)
		draw_line(Vector2(-15.0, -27.0), Vector2(15.0, -27.0), body_col, 5.0)
		draw_line(Vector2(-18.0, -7.0), Vector2(18.0, -7.0), body_col, 10.0)
	if marked:
		draw_line(Vector2(-half * 0.6, 0.0), Vector2(half * 0.6, 0.0),
				Feel.COL_NEWSPRINT, 4.0)
