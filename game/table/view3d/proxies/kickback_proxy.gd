class_name KickbackProxy3D
extends HardwareProxy3D
## The boys on the corner: a kicker post in the outlane with an insert that shows whether
## they are ready to throw the ball back.

var _lamp: StandardMaterial3D = null
var _flash: float = 0.0


func build() -> void:
	var size: Vector2 = source.get("_size")
	var S := TableSpace.SCALE
	var post := BoxMesh.new()
	post.size = Vector3(size.x * S * 0.5, 0.34, 0.12)
	var pm := mesh_node(post, lib.chrome_dark(), "Kicker")
	pm.position = Vector3(0.0, 0.17, size.y * S * 0.5)
	_lamp = lib.lamp(Color(1.0, 0.72, 0.30))
	var insert := BoxMesh.new()
	insert.size = Vector3(size.x * S * 0.6, 0.014, size.y * S * 0.5)
	var im := mesh_node(insert, _lamp, "Insert")
	im.position.y = 0.007


func sync(delta: float) -> void:
	super.sync(delta)
	if not visible:
		return
	var k := source as Kickback
	var f := float(peek(&"_flash", 0.0))
	drive_lamp(_lamp, (1.3 if k.ready_to_fire() else 0.05) + f * 3.0, delta, 10.0)
