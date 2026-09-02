class_name BallProxy3D
extends HardwareProxy3D
## The steel, as a sphere that actually rolls. Rides at floor height, lifts onto whichever
## ramp the sim says it is climbing, and wears the guy's identity skin (BallDesign) so the
## Roll Call face and the live ball still match.

var _mesh: MeshInstance3D = null
var _shadow: MeshInstance3D = null
var _shadow_mat: StandardMaterial3D = null
var _roll: Basis = Basis.IDENTITY
var _design_id: int = -1
var _lift: float = 0.0


func build() -> void:
	follow_transform = false
	var sphere := SphereMesh.new()
	sphere.radius = TableSpace.ball_radius()
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 28
	sphere.rings = 14
	_mesh = mesh_node(sphere, null, "Sphere")
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var disc := PlaneMesh.new()
	disc.size = Vector2.ONE * sphere.radius * 2.4
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_texture = _blob()
	_shadow_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.6)
	_shadow = mesh_node(disc, _shadow_mat, "Blob")
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_design()


func _blob() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var d := Vector2(float(x) + 0.5 - n * 0.5, float(y) + 0.5 - n * 0.5).length() / (n * 0.5)
			img.set_pixel(x, y, Color(0, 0, 0, clampf(1.0 - d * d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _apply_design() -> void:
	var d: Dictionary = source.call(&"design") if source.has_method(&"design") else BallDesign.anonymous()
	var id := int(d.get("id", 0))
	if id == _design_id:
		return
	_design_id = id
	_mesh.material_override = lib.ball(d)


func lift() -> float:
	return _lift


func sync(delta: float) -> void:
	if not alive():
		return
	visible = true
	_apply_design()
	var p := source_origin()
	var floor_h := TableSpace.floor_height(p)
	var ramp_h: float = view.call(&"ramp_height_for", source)
	var base := ramp_h if ramp_h >= 0.0 else floor_h
	_lift = base
	var r := TableSpace.ball_radius()
	global_position = TableSpace.to3(p, base + r)
	var v := (source as RigidBody2D).linear_velocity * TableSpace.SCALE
	var v3 := Vector3(v.x, 0.0, v.y)
	var speed := v3.length()
	if speed > 0.001 and delta > 0.0:
		var axis := Vector3.UP.cross(v3).normalized()
		_roll = Basis(axis, speed * delta / r) * _roll
		_roll = _roll.orthonormalized()
	_mesh.basis = _roll
	# contact shadow sits on whatever the ball is over and fades as it climbs away
	var under := floor_h if ramp_h < 0.0 else floor_h
	_shadow.global_position = TableSpace.to3(p, under + 0.008)
	var gap := maxf(base - floor_h, 0.0)
	_shadow_mat.albedo_color.a = 0.62 / (1.0 + gap * 3.0)
	_shadow.scale = Vector3.ONE * (1.0 + gap * 0.8)
