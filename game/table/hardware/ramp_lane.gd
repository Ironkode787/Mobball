class_name RampLane
extends Node3D
## A real ramp: a swept steel channel the ball rolls in, from a mouth on one storey to a
## crest on another (or back to the field). Nothing here steers the ball — a hard shot makes
## the top, a soft one dies part-way and rolls back out the way it came, because gravity.
## Two sensors turn that into game events: the mouth (`entered` going up, `rolled_back`
## coming down while still on the climb) and the crest (`crested`).
##
## The path is table space (x, height, z). The channel's floor is what the ball rides; the
## rails are drawn as a wireform so the ball stays visible in it.

signal entered(speed: float)
signal crested(speed: float)
signal rolled_back(speed: float)

const CHANNEL_WIDTH := 0.36
const WALL_HEIGHT := 0.50
## Per-lane wall height; short drop chutes that run under another rail use lower walls.
var wall_height: float = WALL_HEIGHT
const RAIL_RADIUS := 0.022
const SUBDIVISIONS := 16
## Rails above the ball's centre lean in over the channel so a fast ball in a bend cannot
## climb out; the opening between the lips is narrower than the ball.
const LIP := 0.09
## The mouth flares out over this length so an off-centre shot is gathered, not bounced.
const FLARE_LENGTH := 0.55
const FLARE_WIDTH := 0.72

## Width of the flared mouth for this ramp (a deck mouth between toys wants a narrower one).
var flare_width: float = FLARE_WIDTH

@export var id: StringName = &"ramp"

var points: PackedVector3Array = PackedVector3Array()
var entry_size: Vector2 = Vector2(0.46, 0.30)
## Scoring gate only: `entered` fires for a ball crossing the mouth up the ramp faster than
## this. Physics decides whether it climbs.
var entry_speed: float = 0.0
var color: Color = Color("B9BEC4")

var _body: StaticBody3D = null
var _mouth: Area3D = null
var _crest: Area3D = null
var _present: bool = true
var _riding: bool = false
var _ball: Ball = null
var _ride_ball: Ball = null
var _samples: PackedVector3Array = PackedVector3Array()
var _cum: PackedFloat32Array = PackedFloat32Array()
var _total: float = 0.0
var _flash: float = 0.0
var _mouth_lamp: StandardMaterial3D = null
var _mouth_dir: Vector3 = Vector3(0, 0, -1)


func configure(p_id: StringName, path: PackedVector3Array) -> void:
	id = p_id
	points = path


func _ready() -> void:
	if points.size() < 2:
		return
	_samples = _smooth(points)
	_cum = PackedFloat32Array()
	_cum.append(0.0)
	_total = 0.0
	for i in range(_samples.size() - 1):
		_total += _samples[i].distance_to(_samples[i + 1])
		_cum.append(_total)
	_mouth_dir = (_samples[1] - _samples[0]).normalized()
	_build_channel()
	_build_sensors()
	_build_look()
	_apply_collision()


## Catmull-Rom through the authored points, so the channel curves instead of kinking.
static func _smooth(pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := pts.size()
	for i in range(n - 1):
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, n - 1)]
		for k in range(SUBDIVISIONS):
			var t := float(k) / float(SUBDIVISIONS)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t
					+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[n - 1])
	return out


func _frames() -> Array:
	# [center, right(unit, horizontal), tangent, half_width, up(unit)]
	var out: Array = []
	for i in range(_samples.size()):
		var t := (_samples[mini(i + 1, _samples.size() - 1)] - _samples[maxi(i - 1, 0)])
		t.y = 0.0
		t = t.normalized() if t.length() > 0.001 else Vector3(0, 0, -1)
		var right := Vector3(-t.z, 0.0, t.x)
		out.append([_samples[i], right, t, half_width_at(_cum[i]), Vector3.UP])
	return out


## Half the channel width at rail distance `s`: flared at the mouth, snug beyond it.
func half_width_at(s: float) -> float:
	if entry_speed <= -1000.0:
		return CHANNEL_WIDTH * 0.5          # return chutes start on a floor: no flare
	var f := clampf(s / FLARE_LENGTH, 0.0, 1.0)
	return lerpf(flare_width, CHANNEL_WIDTH, smoothstep(0.0, 1.0, f)) * 0.5


## Length of floor at the mouth built without walls: a ball that fails the climb and rolls
## back out can leave sideways instead of resting in a walled pocket.
var open_mouth_length: float = 0.0


func _build_channel() -> void:
	_body = WallBuilder.make_body("Channel", Feel.LAYER_WALLS,
			Feel.make_material(Feel.STEEL_FRICTION, Feel.STEEL_BOUNCE))
	add_child(_body)
	var faces := PackedVector3Array()
	var frames := _frames()
	for i in range(frames.size() - 1):
		var c0: Vector3 = frames[i][0]
		var r0: Vector3 = frames[i][1] * float(frames[i][3])
		var c1: Vector3 = frames[i + 1][0]
		var r1: Vector3 = frames[i + 1][1] * float(frames[i + 1][3])
		var up0: Vector3 = frames[i][4] * wall_height
		var up1: Vector3 = frames[i + 1][4] * wall_height
		# floor
		_quad(faces, c0 - r0, c0 + r0, c1 + r1, c1 - r1)
		if _cum[i] < open_mouth_length:
			continue
		# walls, with inward lips along the top
		_quad(faces, c0 - r0, c1 - r1, c1 - r1 + up1, c0 - r0 + up0)
		_quad(faces, c0 + r0 + up0, c1 + r1 + up1, c1 + r1, c0 + r0)
		var l0 := r0.normalized() * LIP
		var l1 := r1.normalized() * LIP
		_quad(faces, c0 - r0 + up0, c1 - r1 + up1, c1 - r1 + up1 + l1, c0 - r0 + up0 + l0)
		_quad(faces, c0 + r0 + up0 - l0, c1 + r1 + up1 - l1, c1 + r1 + up1, c0 + r0 + up0)
	var shape := CollisionShape3D.new()
	var mesh_shape := ConcavePolygonShape3D.new()
	mesh_shape.backface_collision = true
	mesh_shape.set_faces(faces)
	shape.shape = mesh_shape
	shape.name = "ChannelShape"
	_body.add_child(shape)


static func _quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	faces.append(a); faces.append(b); faces.append(c)
	faces.append(a); faces.append(c); faces.append(d)


func _build_sensors() -> void:
	_mouth = _sensor("Mouth", _samples[0] + _mouth_dir * 0.12, entry_size)
	_mouth.body_entered.connect(_on_mouth)
	var last := _samples[_samples.size() - 1]
	var tail := (last - _samples[_samples.size() - 2]).normalized()
	_crest = _sensor("Crest", last - tail * 0.15, Vector2(CHANNEL_WIDTH + 0.1, 0.3))
	_crest.body_entered.connect(_on_crest)


func _sensor(p_name: String, at: Vector3, size: Vector2) -> Area3D:
	var a := Area3D.new()
	a.name = p_name
	a.collision_layer = Feel.LAYER_ZONES
	a.collision_mask = Feel.LAYER_BALL
	a.monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 0.6, size.y)
	cs.shape = box
	a.position = at + Vector3(0.0, 0.2, 0.0)
	var flat := Vector2(_mouth_dir.x, _mouth_dir.z)
	a.rotation.y = Layout.yaw_facing(flat) if flat.length() > 0.001 else 0.0
	a.add_child(cs)
	add_child(a)
	return a


func _build_look() -> void:
	var lib := MaterialLib.shared()
	var frames := _frames()
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var low_left := PackedVector3Array()
	var low_right := PackedVector3Array()
	for f in frames:
		var c: Vector3 = f[0]
		var r: Vector3 = f[1]
		var hw: float = float(f[3]) + 0.01
		var up: Vector3 = f[4]
		left.append(c - r * hw + up * (wall_height * 0.9))
		right.append(c + r * hw + up * (wall_height * 0.9))
		low_left.append(c - r * (hw - 0.05) + up * 0.03)
		low_right.append(c + r * (hw - 0.05) + up * 0.03)
	var st := MeshLib.begin()
	MeshLib.tube(st, left, RAIL_RADIUS, 7)
	MeshLib.tube(st, right, RAIL_RADIUS, 7)
	MeshLib.tube(st, low_left, RAIL_RADIUS * 0.9, 7)
	MeshLib.tube(st, low_right, RAIL_RADIUS * 0.9, 7)
	var next_tie := 0.0
	var next_post := 0.3
	for i in range(frames.size()):
		var s := _cum[i]
		var c: Vector3 = frames[i][0]
		var r: Vector3 = frames[i][1]
		var hw: float = float(frames[i][3])
		if s >= next_tie:
			MeshLib.tube(st, PackedVector3Array([left[i], low_left[i]]), RAIL_RADIUS * 0.5, 5)
			MeshLib.tube(st, PackedVector3Array([right[i], low_right[i]]), RAIL_RADIUS * 0.5, 5)
			MeshLib.tube(st, PackedVector3Array([low_left[i], low_right[i]]), RAIL_RADIUS * 0.5, 5)
			next_tie += 0.55
		if s >= next_post and c.y > 0.12:
			var floor_y := _floor_height_under(c)
			for side: Vector3 in [c - r * hw, c + r * hw]:
				MeshLib.tube(st, PackedVector3Array([Vector3(side.x, floor_y, side.z), side]), RAIL_RADIUS * 0.6, 5, false)
			next_post += 0.9
	var mi := MeshInstance3D.new()
	var mat := lib.steel().duplicate() as StandardMaterial3D
	mat.albedo_color = color
	mi.mesh = MeshLib.finish(st, mat)
	mi.name = "Wireform"
	add_child(mi)
	_mouth_lamp = lib.lamp(Color(1.0, 0.82, 0.40))
	var mouth := BoxMesh.new()
	mouth.size = Vector3(minf(entry_size.x * 0.8, 0.6), 0.012, entry_size.y * 0.5)
	var mm := MeshInstance3D.new()
	mm.mesh = mouth
	mm.material_override = _mouth_lamp
	mm.position = _samples[0] + Vector3(0.0, 0.006, 0.0) + _mouth_dir * 0.3
	mm.name = "MouthLamp"
	add_child(mm)


## Posts stand on whatever storey is under the rail; the segments override this per deck.
func _floor_height_under(_at: Vector3) -> float:
	return 0.0


func set_ball(b: Ball) -> void:
	_ball = b
	if _riding and b != _ride_ball:
		_riding = false


func riding() -> bool:
	return _riding and _ride_ball != null and is_instance_valid(_ride_ball)


func length() -> float:
	return _total


## How far along the rail the riding ball is, in units (nearest sample).
func progress() -> float:
	if not riding():
		return 0.0
	var p := _ride_ball.table_position()
	var best := 0.0
	var best_d := INF
	for i in range(_samples.size()):
		var d := _samples[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = _cum[i]
	return best


func ride_speed() -> float:
	return _ride_ball.speed() if riding() else 0.0


func point_at(s: float) -> Vector3:
	if _samples.is_empty():
		return position
	var t := clampf(s, 0.0, _total)
	for i in range(_samples.size() - 1):
		if t <= _cum[i + 1] or i == _samples.size() - 2:
			var seg := _cum[i + 1] - _cum[i]
			var f := 0.0 if seg <= 0.0 else clampf((t - _cum[i]) / seg, 0.0, 1.0)
			return _samples[i].lerp(_samples[i + 1], f)
	return _samples[_samples.size() - 1]


func mouth_position() -> Vector3:
	return _samples[0] if not _samples.is_empty() else position


func crest_position() -> Vector3:
	return _samples[_samples.size() - 1] if not _samples.is_empty() else position


func _on_mouth(body: Node3D) -> void:
	if not (body is Ball) or not _present:
		return
	var ball := body as Ball
	var v := ball.local_velocity()
	var along := v.dot(_mouth_dir)
	if along > 0.0:
		if along < entry_speed:
			return                                  # too slow to count as a shot at it
		_riding = true
		_ride_ball = ball
		TableScore.hit(StringName(String(id) + "_entry"), ball, along)
		entered.emit(along)
	elif _riding and ball == _ride_ball:
		_riding = false
		rolled_back.emit(-along)


func _on_crest(body: Node3D) -> void:
	if not (body is Ball) or not _present:
		return
	var ball := body as Ball
	if not _riding or ball != _ride_ball:
		# a ball that entered from the far end (a return lane) still counts as cresting when
		# it leaves: the crest is simply the end of the channel
		if entry_speed > -1000.0:
			return
	_riding = false
	_flash = 1.0
	crested.emit(ball.speed())


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.0, 0.0)
	if _riding and (_ride_ball == null or not is_instance_valid(_ride_ball)):
		_riding = false


func _process(delta: float) -> void:
	if _mouth_lamp == null:
		return
	var wanted := 0.25
	if _riding:
		wanted = 2.4
	_mouth_lamp.emission_energy_multiplier = lerpf(_mouth_lamp.emission_energy_multiplier,
			wanted + _flash * 2.0, 1.0 - exp(-8.0 * delta))


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_riding = false
	_apply_collision()


func is_hardware_active() -> bool:
	return _present


func _apply_collision() -> void:
	if _body != null:
		_body.collision_layer = Feel.LAYER_WALLS if _present else 0
	for a: Area3D in [_mouth, _crest]:
		if a == null:
			continue
		a.collision_layer = Feel.LAYER_ZONES if _present else 0
		a.collision_mask = Feel.LAYER_BALL if _present else 0


func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.IDLE
	if not _present:
		state = TableVisualState.VisualState.DISABLED
	elif _riding:
		state = TableVisualState.VisualState.ACTIVE
	elif _flash > 0.0:
		state = TableVisualState.VisualState.COMPLETED
	else:
		state = TableVisualState.VisualState.ARMED
	return TableVisualState.state_token(state, {&"held": _riding, &"flash": _flash > 0.0})


func visual_token() -> Dictionary:
	return visual_state()
