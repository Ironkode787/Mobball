class_name RampProxy3D
extends HardwareProxy3D
## A wireform ramp: two chrome rails on posts, climbing from the storey it leaves to the
## storey it reaches, with a mouth insert that lights when the shot is worth taking. The
## height profile here is the one BallProxy3D lifts the ball by, so what climbs is what shows.

const RAIL_GAP := 0.17
const RAIL_R := 0.026
const STEP := 0.22          ## metres between samples along the rail
const HUMP_FLAT := 0.34     ## how high a ramp between equal storeys arches over the field
const HUMP_CLIMB := 0.12

var _samples: PackedVector2Array = PackedVector2Array()    ## metres, xz
var _cum: PackedFloat32Array = PackedFloat32Array()
var _total_px: float = 0.0
var _h_start: float = 0.0
var _h_end: float = 0.0
var _mouth_lamp: StandardMaterial3D = null


func build() -> void:
	follow_transform = false
	var r := source as RampLane
	var pts := r.points
	if pts.size() < 2:
		return
	var S := TableSpace.SCALE
	_total_px = r.length()
	_h_start = TableSpace.floor_height(pts[0])
	_h_end = TableSpace.floor_height(pts[pts.size() - 1])
	# resample the polyline so the height curve is smooth even where the author was sparse
	var path_px: Array[Vector2] = []
	var along_px: PackedFloat32Array = PackedFloat32Array()
	var acc := 0.0
	path_px.append(pts[0])
	along_px.append(0.0)
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		var n := maxi(int(ceil(seg * S / STEP)), 1)
		for k in range(1, n + 1):
			var f := float(k) / float(n)
			path_px.append(pts[i].lerp(pts[i + 1], f))
			along_px.append(acc + seg * f)
		acc += seg
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var center := PackedVector3Array()
	for i in range(path_px.size()):
		var p := path_px[i]
		var s_px := along_px[i]
		var h := height_at(s_px)
		var t2 := (path_px[mini(i + 1, path_px.size() - 1)] - path_px[maxi(i - 1, 0)]).normalized()
		var n2 := Vector2(-t2.y, t2.x) * RAIL_GAP
		var c := Vector3(p.x * S, h, p.y * S)
		center.append(c)
		left.append(c + Vector3(n2.x, 0.0, n2.y))
		right.append(c - Vector3(n2.x, 0.0, n2.y))
	var st := View3DMesh.begin()
	View3DMesh.tube(st, left, RAIL_R, 7)
	View3DMesh.tube(st, right, RAIL_R, 7)
	# cross ties and posts
	var next_tie := 0.0
	var next_post := 0.35
	for i in range(center.size()):
		var s_m := along_px[i] * S
		if s_m >= next_tie:
			View3DMesh.tube(st, PackedVector3Array([left[i] - Vector3(0, RAIL_R * 0.8, 0), right[i] - Vector3(0, RAIL_R * 0.8, 0)]), RAIL_R * 0.55, 5)
			next_tie += 0.42
		if s_m >= next_post:
			var floor_h := TableSpace.floor_height(path_px[i])
			if center[i].y - floor_h > 0.12:
				for side in [left[i], right[i]]:
					View3DMesh.tube(st, PackedVector3Array([Vector3(side.x, floor_h, side.z), side - Vector3(0, RAIL_R, 0)]), RAIL_R * 0.5, 5, false)
			next_post += 1.1
	mesh_node(View3DMesh.finish(st, lib.steel()), null, "Wireform")
	# the mouth: a lit insert where the shot begins
	_mouth_lamp = lib.lamp(Color(1.0, 0.82, 0.40))
	var mouth := BoxMesh.new()
	mouth.size = Vector3(minf(r.entry_size.x * S * 0.8, 0.9), 0.016, r.entry_size.y * S * 0.5)
	var mm := mesh_node(mouth, _mouth_lamp, "Mouth")
	mm.position = TableSpace.to3(r.entry_center, _h_start + 0.008)


## Height of the rail above the ground floor at rail distance `s_px`.
func height_at(s_px: float) -> float:
	if _total_px <= 0.0:
		return _h_start
	var f := clampf(s_px / _total_px, 0.0, 1.0)
	var base := lerpf(_h_start, _h_end, smoothstep(0.0, 1.0, f))
	var hump := HUMP_FLAT if is_equal_approx(_h_start, _h_end) else HUMP_CLIMB
	return base + hump * sin(PI * f)


## Lift for `ball` if it is the one riding this rail; negative when it is not.
func height_for_ball(ball: Ball) -> float:
	var r := source as RampLane
	if not r.riding():
		return -1.0
	if peek(&"_ball", null) != ball:
		return -1.0
	return height_at(r.progress())


func sync(delta: float) -> void:
	super.sync(delta)
	if not visible or _mouth_lamp == null:
		return
	var tok := token()
	var state := state_name(tok)
	var wanted := 0.2
	if state == &"armed":
		wanted = 1.4
	elif state == &"active":
		wanted = 2.6
	drive_lamp(_mouth_lamp, wanted, delta, 8.0)
