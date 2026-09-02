class_name Slingshot
extends StaticBody3D
## The sling triangle: rubber over a lit plastic plinth, with a kicker behind the long face.
## The starter table's slings are dead rubber — present, bouncy, silent — until Corner Boys
## power the face.

@export var id: StringName = &"sling"
@export var value: int = Feel.SLING_VALUE
@export var group: StringName = &"slings"
@export var passive_when_inactive: bool = false

var points: PackedVector2Array = PackedVector2Array()    ## plan, relative to the centroid
var face_normal: Vector2 = Vector2(0.0, -1.0)
var _present: bool = true
var _powered: bool = true
var _cooldown: float = 0.0
var _pulse: float = 0.0
var _band: Area3D = null
var _inside: Array[Ball] = []
var _lamp: StandardMaterial3D = null


func configure(p_id: StringName, p0: Vector2, p1: Vector2, p2: Vector2) -> void:
	id = p_id
	var centroid := (p0 + p1 + p2) / 3.0
	position = Layout.p3(centroid)
	points = PackedVector2Array([p0 - centroid, p1 - centroid, p2 - centroid])


func _ready() -> void:
	collision_layer = Feel.LAYER_HARDWARE
	collision_mask = 0
	physics_material_override = Feel.make_material(Feel.RUBBER_FRICTION, Feel.RUBBER_BOUNCE)
	if points.size() != 3:
		return
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for p in points:
		pts.append(Vector3(p.x, 0.0, p.y))
		pts.append(Vector3(p.x, Layout.WALL_HEIGHT, p.y))
	hull.points = pts
	shape.shape = hull
	shape.name = "Body"
	add_child(shape)

	var a := points[1]
	var b := points[2]
	var edge := b - a
	var n := Vector2(-edge.y, edge.x).normalized()
	if n.dot((a + b) * 0.5) < 0.0:
		n = -n
	face_normal = n
	_band = Area3D.new()
	_band.name = "Face"
	_band.collision_layer = Feel.LAYER_ZONES
	_band.collision_mask = Feel.LAYER_BALL
	_band.monitorable = false
	var bs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(edge.length(), 0.5, Feel.BALL_RADIUS * 1.5)
	bs.shape = box
	var mid := (a + b) * 0.5 + n * (Feel.BALL_RADIUS * 0.75)
	bs.position = Vector3(mid.x, 0.25, mid.y)
	bs.rotation.y = atan2(-edge.y, edge.x)
	_band.add_child(bs)
	add_child(_band)
	_band.body_entered.connect(_on_ball_entered)
	_band.body_exited.connect(_on_ball_exited)
	_build_look()
	_apply_collision()


func _build_look() -> void:
	var lib := MaterialLib.shared()
	var inner := PackedVector2Array()
	for p in points:
		inner.append(p * 0.62)
	var st := MeshLib.begin()
	MeshLib.prism(st, points, 0.26, 0.04, false, 1.0)
	var band := MeshInstance3D.new()
	band.mesh = MeshLib.finish(st, lib.rubber())
	band.name = "Band"
	add_child(band)
	_lamp = lib.lamp(Color(1.0, 0.72, 0.30))
	var st2 := MeshLib.begin()
	MeshLib.prism(st2, inner, 0.36, 0.0, false, 1.0)
	var plinth := MeshInstance3D.new()
	plinth.mesh = MeshLib.finish(st2, _lamp)
	plinth.name = "Plinth"
	add_child(plinth)
	var st3 := MeshLib.begin()
	for p in points:
		MeshLib.post(st3, p, 0.045, 0.40, 0.0, 10)
	var posts := MeshInstance3D.new()
	posts.mesh = MeshLib.finish(st3, lib.chrome_dark())
	posts.name = "Posts"
	add_child(posts)


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 8.0, 0.0)
	if _lamp != null:
		_lamp.emission_energy_multiplier = lerpf(_lamp.emission_energy_multiplier,
				(0.25 if _powered else 0.0) + _pulse * 3.0, 1.0 - exp(-18.0 * delta))


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not _powered or _inside.is_empty():
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


func _on_ball_exited(body: Node3D) -> void:
	if body is Ball:
		_inside.erase(body as Ball)


func _on_ball_entered(body: Node3D) -> void:
	if not (body is Ball):
		return
	_inside.append(body as Ball)
	if not _powered or _cooldown > 0.0:
		return
	_kick(body as Ball)


func _kick(ball: Ball) -> void:
	if not _powered:
		return
	_cooldown = Feel.SLING_COOLDOWN
	var n := Vector3(face_normal.x, 0.0, face_normal.y).rotated(Vector3.UP, rotation.y).normalized()
	ball.kick(n * Feel.SLING_IMPULSE)
	_pulse = 1.0
	AudioDirector.play(&"sling_hit")
	TableScore.earn(group, float(value), id, ball, Feel.SLING_IMPULSE)


func set_hardware_active(active: bool) -> void:
	_powered = active
	_present = active or passive_when_inactive
	visible = _present
	_inside.clear()
	_apply_collision()


func is_present() -> bool:
	return _present


func is_powered() -> bool:
	return _powered


func _apply_collision() -> void:
	collision_layer = Feel.LAYER_HARDWARE if _present else 0
	if _band != null:
		_band.collision_layer = Feel.LAYER_ZONES if _present and _powered else 0
		_band.collision_mask = Feel.LAYER_BALL if _present and _powered else 0


func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.IDLE
	var mods: Array[StringName] = []
	if not _present:
		state = TableVisualState.VisualState.DISABLED
	elif _pulse > 0.0:
		state = TableVisualState.VisualState.ACTIVE
		mods.append(&"pulse")
	elif _powered:
		state = TableVisualState.VisualState.ARMED
	return TableVisualState.state_token(state, mods)
