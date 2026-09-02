class_name TableView3D
extends Node3D
## The 3D playfield. The 2D table under `game/table/` stays the simulation of record — every
## collider, sensor and rule lives there and the sims keep measuring it — and this node is
## its room: a lit, perspective, multi-storey rendering of the same geometry, rebuilt from
## the colliders so the picture can never lie about where the ball can go.
##
## How the two worlds meet:
##
##   * `TableSpace` maps table px onto metres. The main field is the ground floor; the Club,
##     the Penthouse and City Hall are the second storey, DECK_HEIGHT up. Ramps climb between.
##   * Every piece of hardware gets a `HardwareProxy3D` that follows it and restyles itself
##     from the piece's own `visual_state()` token. Proxies are created for whatever is in the
##     table's tree — new nodes (balls, late hardware) are picked up from `SceneTree.node_added`.
##   * The Camera3D is slaved to the 2D `CameraRig` through the canvas transform, so the view
##     the sim frames (and the nudge kick) is the view the player sees, tilted into perspective.
##   * `Presentation` asks this node to project table points to the screen, so feedback still
##     lands on its source.
##
## Runs in the root viewport underneath the 2D canvas: the 2D table hides its own drawing and
## every CanvasLayer (HUD, screens, feedback) keeps painting on top. Headless, this is inert.

const ENV_2D_FALLBACK := "KINGPIN_TABLE_2D"
const CAMERA_TILT_DEG := 27.0
const CAMERA_FOV_DEG := 46.0
const CAMERA_HEIGHT_SMOOTH := 5.0
const MAX_OMNI_LIGHTS := 6

var table: Node2D = null
var camera_rig: Camera2D = null
var lib := View3DMaterials.new()
var camera: Camera3D = null
var environment: WorldEnvironment = null
var sun: DirectionalLight3D = null
var shadows_enabled: bool = true

var _proxies: Array[HardwareProxy3D] = []
var _proxied: Dictionary = {}          ## source instance id -> proxy
var _ramps: Array = []                 ## RampProxy3D, for ball lift
var _balls: Array = []                 ## BallProxy3D
var _room: Node3D = null
var _slabs: Array[Dictionary] = []     ## { node: MeshInstance3D, segment: Node }
var _room_bounds: Rect2 = Rect2()
var _cam_h: float = 0.0
var _cam_h_init: bool = false
var _pending: Array[Node] = []
var _lamps: Array[OmniLight3D] = []


static func enabled() -> bool:
	if OS.get_environment(ENV_2D_FALLBACK) == "1":
		return false
	return true


func setup(p_table: Node2D, p_camera: Camera2D) -> void:
	table = p_table
	camera_rig = p_camera
	name = "TableView3D"
	_build_environment()
	_build_camera()
	_build_room()
	_scan(table)
	get_tree().node_added.connect(_on_node_added)
	if Presentation != null:
		Presentation.set("projector", self)
	table.visible = false


func _exit_tree() -> void:
	if Presentation != null and Presentation.get("projector") == self:
		Presentation.set("projector", null)
	if table != null and is_instance_valid(table):
		table.visible = true


# ---------------------------------------------------------------- environment -----


func _build_environment() -> void:
	environment = WorldEnvironment.new()
	environment.name = "Environment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = lib.city_color(&"ink_glass", Feel.COL_INK).darkened(0.35)
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	# A dim warm room for the metal to reflect: no sun disc (it would bloom through the
	# backbox), a soft bright band at the horizon so the ball reads as chrome.
	sky_mat.sky_top_color = Color("1C1814")
	sky_mat.sky_horizon_color = Color("8A7452")
	sky_mat.ground_horizon_color = Color("4A3A28")
	sky_mat.ground_bottom_color = Color("0A0806")
	sky_mat.sun_angle_max = 0.0
	sky_mat.sun_curve = 0.0
	sky_mat.energy_multiplier = 0.8
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("3A3430")
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.environment = env
	add_child(environment)

	sun = DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.light_color = Color(1.0, 0.92, 0.80)
	sun.light_energy = 1.15
	sun.shadow_enabled = shadows_enabled
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 48.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.5
	sun.rotation_degrees = Vector3(-58.0, 34.0, 0.0)
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_color = Color(0.55, 0.72, 0.80)
	fill.light_energy = 0.28
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-40.0, -140.0, 0.0)
	add_child(fill)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = CAMERA_FOV_DEG
	camera.near = 0.4
	camera.far = 90.0
	add_child(camera)
	camera.current = true
	_sync_camera(0.0)


## A general-illumination lamp from the budgeted pool. Returns null when the pool is spent;
## callers must cope (emissive materials carry the read on their own).
func request_lamp(at: Vector3, color: Color, energy: float, range_m: float) -> OmniLight3D:
	if _lamps.size() >= MAX_OMNI_LIGHTS:
		return null
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.position = at
	add_child(l)
	_lamps.append(l)
	return l


# ---------------------------------------------------------------------- room -----


func _build_room() -> void:
	if _room != null:
		_room.queue_free()
	_room = Node3D.new()
	_room.name = "Room"
	add_child(_room)
	_slabs.clear()
	var b: Rect2 = table.call(&"bounds") if table.has_method(&"bounds") else Rect2(0, 0, 1080, 1920)
	_room_bounds = b
	var S := TableSpace.SCALE
	var left := ProgressionTable.PLAY_LEFT
	var right := ProgressionTable.LANE_RIGHT
	var bottom := ProgressionTable.PLAY_BOTTOM
	var wall := ProgressionTable.OUTER_THICK
	var top_px := minf(b.position.y, 0.0)

	# Ground floor: felt out to the outer wall's centre line, wood in the shooter lane.
	_slab_mesh(Rect2(left - wall, -10.0, right - left + wall * 2.0, bottom - (-10.0) + wall), -0.02, 0.02,
			lib.felt(), lib.wood_dark(), "Felt")
	_slab_mesh(Rect2(ProgressionTable.LANE_LEFT - 4.0, ProgressionTable.DIVIDER_TOP,
			ProgressionTable.LANE_RIGHT - ProgressionTable.LANE_LEFT + 4.0,
			ProgressionTable.LANE_FLOOR_Y - ProgressionTable.DIVIDER_TOP), 0.0, 0.012,
			lib.wood(), lib.wood_dark(), "ShooterLane")

	# Cabinet: side boards the full length of whatever the career has built, a front board
	# under the player's hands, a brass lockdown bar.
	var cab_top := top_px - 40.0
	var side_len := (bottom + 60.0 - cab_top) * S
	var side_z := (cab_top + (bottom + 60.0)) * 0.5 * S
	var cab_h := TableSpace.CABINET_HEIGHT
	for sx in [left - wall - 14.0, right + wall + 14.0]:
		var st := View3DMesh.begin()
		View3DMesh.box(st, Vector3(sx * S, cab_h * 0.5 - 0.3, side_z), Vector3(0.28, cab_h + 0.3, side_len))
		_add_room_mesh(View3DMesh.finish(st, lib.wood_dark()), "CabinetSide")
	var front := View3DMesh.begin()
	View3DMesh.box(front, Vector3(540.0 * S, cab_h * 0.5 - 0.3, (bottom + 46.0) * S),
			Vector3((right - left + wall * 2.0 + 56.0) * S, cab_h + 0.3, 0.32))
	_add_room_mesh(View3DMesh.finish(front, lib.wood_dark()), "CabinetFront")
	var bar := View3DMesh.begin()
	View3DMesh.box(bar, Vector3(540.0 * S, cab_h + 0.02, (bottom + 46.0) * S),
			Vector3((right - left + wall * 2.0 + 56.0) * S, 0.09, 0.42))
	_add_room_mesh(View3DMesh.finish(bar, lib.brass()), "LockdownBar")

	# The storm grate the drain is lit from below by (docs/02 §4).
	var grate := PlaneMesh.new()
	grate.size = Vector2(ProgressionTable.CENTRE_DRAIN_SIZE.x * S, ProgressionTable.CENTRE_DRAIN_SIZE.y * S)
	var grate_mat := StandardMaterial3D.new()
	grate_mat.albedo_texture = lib.grate_texture()
	grate_mat.emission_enabled = true
	grate_mat.emission_texture = lib.grate_texture()
	grate_mat.emission = Color.WHITE
	grate_mat.emission_energy_multiplier = 0.9
	grate_mat.roughness = 0.6
	var grate_mi := MeshInstance3D.new()
	grate_mi.mesh = grate
	grate_mi.material_override = grate_mat
	grate_mi.position = TableSpace.to3(ProgressionTable.CENTRE_DRAIN_AT + Vector2(0.0, 40.0), 0.006)
	grate_mi.name = "StormGrate"
	_room.add_child(grate_mi)

	# The backbox: the illuminated backglass standing at the head of the machine.
	var glass_tex: Texture2D = null
	if Presentation != null and Presentation.art != null:
		glass_tex = Presentation.art.resolve(&"table.backglass.eastport", null, false)
	var head_z := (cab_top - 30.0) * S
	var head_h := TableSpace.floor_height(Vector2(540.0, cab_top))
	var box := View3DMesh.begin()
	View3DMesh.box(box, Vector3(540.0 * S, head_h + 1.9, head_z - 0.3),
			Vector3((right - left + wall * 2.0 + 56.0) * S, 4.4, 0.6))
	_add_room_mesh(View3DMesh.finish(box, lib.wood_dark()), "Backbox")
	if glass_tex != null:
		var glass := PlaneMesh.new()
		glass.size = Vector2((right - left) * S * 0.9, (right - left) * S * 0.9 * float(glass_tex.get_height()) / float(glass_tex.get_width()))
		glass.orientation = PlaneMesh.FACE_Z
		# lit from behind like a real backglass: unshaded, so the room light cannot wash it out
		var gm := lib.art(glass_tex, 0.0)
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color(1.15, 1.15, 1.15)
		gm.cull_mode = BaseMaterial3D.CULL_BACK
		var gmi := MeshInstance3D.new()
		gmi.mesh = glass
		gmi.material_override = gm
		gmi.position = Vector3(540.0 * S, head_h + 2.1, head_z + 0.01)
		gmi.name = "Backglass"
		_room.add_child(gmi)

	# Second storey slabs, one per built segment, shown only while that segment stands.
	for seg_name in ["club", "penthouse", "city_hall"]:
		var seg: Variant = table.get(seg_name)
		if seg == null or not (seg is Node) or not (seg as Node).has_method(&"bounds"):
			continue
		var r: Rect2 = (seg as Node).call(&"bounds")
		var tint := Color("7A6AA8") if seg_name == "club" else (Color("8A93B8") if seg_name == "penthouse" else Color("C9B06A"))
		var slab_mat := lib.felt().duplicate() as StandardMaterial3D
		slab_mat.albedo_color = tint.lerp(Color.WHITE, 0.55)
		var mi := _slab_mesh(r.grow(10.0), TableSpace.DECK_HEIGHT - 0.14, 0.14, slab_mat, lib.wood_dark(), "Slab_" + seg_name)
		_slabs.append({"node": mi, "segment": seg})
		# posts holding the storey up along its front edge
		var posts := View3DMesh.begin()
		var front_z := (r.end.y + 10.0) * S
		for i in range(4):
			var x := lerpf(r.position.x, r.end.x, (float(i) + 0.5) / 4.0) * S
			View3DMesh.post(posts, Vector2(x, front_z - 0.12), 0.07, TableSpace.DECK_HEIGHT - 0.14, 0.0, 10)
		var post_mi := _add_room_mesh(View3DMesh.finish(posts, lib.brass_dark()), "Posts_" + seg_name)
		_slabs.append({"node": post_mi, "segment": seg})
	if table.get("plunger") != null:
		var pp := PlungerProxy3D.new()
		_room.add_child(pp)
		pp.setup_plunger(table, lib)
	# general illumination over the flippers: the one lamp every table has
	var gi := request_lamp(TableSpace.to3(Vector2(540.0, 1560.0), 2.6), Color(1.0, 0.9, 0.75), 1.4, 7.0)
	if gi != null:
		gi.name = "FlipperGI"
	_sync_slabs()


func _slab_mesh(r_px: Rect2, base: float, thick: float, top_mat: Material, side_mat: Material,
		p_name: String) -> MeshInstance3D:
	var S := TableSpace.SCALE
	var poly := PackedVector2Array([
		r_px.position * S, Vector2(r_px.end.x, r_px.position.y) * S, r_px.end * S,
		Vector2(r_px.position.x, r_px.end.y) * S,
	])
	var st := View3DMesh.begin()
	View3DMesh.prism(st, poly, thick, base, true, 0.5)
	var mesh := View3DMesh.finish(st, top_mat)
	var mi := _add_room_mesh(mesh, p_name)
	# sides in the side material: cheap trick — a second, slightly inset prism underneath
	if side_mat != top_mat:
		var st2 := View3DMesh.begin()
		View3DMesh.prism(st2, poly, thick - 0.004, base - 0.002, true, 0.5)
		var mi2 := _add_room_mesh(View3DMesh.finish(st2, side_mat), p_name + "Side")
		mi2.scale = Vector3(1.0006, 1.0, 1.0006)
	return mi


func _add_room_mesh(mesh: Mesh, p_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = p_name
	_room.add_child(mi)
	return mi


func _sync_slabs() -> void:
	for s in _slabs:
		var seg: Node = s["segment"]
		var mi: MeshInstance3D = s["node"]
		if not is_instance_valid(seg) or not is_instance_valid(mi):
			continue
		var on := true
		if seg.has_method(&"is_hardware_active"):
			on = bool(seg.call(&"is_hardware_active"))
		mi.visible = on


# ------------------------------------------------------------------- proxies -----


func _on_node_added(node: Node) -> void:
	if table == null or not is_instance_valid(table):
		return
	if node == table or table.is_ancestor_of(node):
		_pending.append(node)


func _scan(root: Node) -> void:
	for child in root.get_children():
		_consider(child)
		_scan(child)


func _consider(node: Node) -> void:
	if not is_instance_valid(node) or _proxied.has(node.get_instance_id()):
		return
	var proxy := _make_proxy(node)
	if proxy == null:
		return
	add_child(proxy)
	proxy.setup(node as Node2D, self)
	_proxies.append(proxy)
	_proxied[node.get_instance_id()] = proxy
	if proxy is RampProxy3D:
		_ramps.append(proxy)
	elif proxy is BallProxy3D:
		_balls.append(proxy)


## Class → proxy. The generic wall proxy is the catch-all for any collider the ball can hit
## that no specialised proxy claims, so nothing physical is ever invisible.
func _make_proxy(node: Node) -> HardwareProxy3D:
	if node is Ball:
		return BallProxy3D.new()
	if node is Flipper:
		return FlipperProxy3D.new()
	if node is Bumper:
		return BumperProxy3D.new()
	if node is Slingshot:
		return SlingshotProxy3D.new()
	if node is StandupTarget or node is DropTarget:
		return TargetProxy3D.new()
	if node is Rollover:
		return RolloverProxy3D.new()
	if node is Spinner:
		return SpinnerProxy3D.new()
	if node is Storefront:
		return StorefrontProxy3D.new()
	if node is RampLane:
		return RampProxy3D.new()
	if node is HoldSaucer:
		return SaucerProxy3D.new()
	if node is OneWayGate:
		return GateProxy3D.new()
	if node is Kickback:
		return KickbackProxy3D.new()
	if node is BossTarget:
		return BossProxy3D.new()
	if node is OrbitLane:
		return OrbitProxy3D.new()
	if node is CityHall or node is Penthouse or node is Docks or node is ClubDeck:
		return SegmentPropsProxy3D.new()
	if node is WallPiece:
		var wp := node as WallPiece
		var p := WallProxy3D.new()
		p.setup_body_deferred(wp.body, wp.walls.chains, self, lib.brass_dark(), false)
		return p
	if node is StaticBody2D:
		return _wall_for_body(node as StaticBody2D)
	return null


func _wall_for_body(body: StaticBody2D) -> HardwareProxy3D:
	var parent := body.get_parent()
	# bodies owned by a specialised proxy's hardware are that proxy's business
	if parent is WallPiece or parent is OneWayGate or parent is Bumper or parent is Slingshot \
			or parent is StandupTarget or parent is DropTarget or parent is Flipper:
		return null
	var live_layer := body.collision_layer
	if body.has_meta(&"live_layer"):
		live_layer = int(body.get_meta(&"live_layer"))
	if live_layer & (Feel.LAYER_WALLS | Feel.LAYER_HARDWARE) == 0:
		return null
	var chains: Array = []
	var tall := false
	var mat: Material = lib.brass_dark()
	# a builder kept by the owner (ProgressionTable._walls, RouletteWheel._walls)
	for field in [&"_walls", &"walls"]:
		var wb: Variant = parent.get(field) if parent != null else null
		if wb is WallBuilder and (wb as WallBuilder).body == body:
			chains = (wb as WallBuilder).chains
	if parent == table and body.name == "Walls":
		tall = true
		mat = lib.wood()
	var p := WallProxy3D.new()
	p.setup_body_deferred(body, chains, self, mat, tall)
	return p


## Ramp lift for a ball, if one is riding it (BallProxy asks every frame).
func ramp_height_for(ball: Ball) -> float:
	for r in _ramps:
		if is_instance_valid(r) and r.alive():
			var h: float = r.height_for_ball(ball)
			if h >= 0.0:
				return h
	return -1.0


# ------------------------------------------------------------------- per frame -----


func _process(delta: float) -> void:
	if table == null or not is_instance_valid(table):
		return
	if not _pending.is_empty():
		for n in _pending:
			if is_instance_valid(n):
				_consider(n)
		_pending.clear()
	for i in range(_proxies.size() - 1, -1, -1):
		var p := _proxies[i]
		if not p.alive():
			_proxies.remove_at(i)
			_ramps.erase(p)
			_balls.erase(p)
			p.queue_free()
			continue
		p.sync(delta)
	_sync_slabs()
	var b: Rect2 = table.call(&"bounds")
	if b != _room_bounds:
		_build_room()
	_sync_camera(delta)


func _sync_camera(delta: float) -> void:
	if camera == null:
		return
	var center := Vector2(540.0, 970.0)
	var view_h := 1959.0
	if camera_rig != null and is_instance_valid(camera_rig) and camera_rig.is_inside_tree():
		var vp := camera_rig.get_viewport()
		var ct := vp.get_canvas_transform()
		var vis := vp.get_visible_rect().size
		center = ct.affine_inverse() * (vis * 0.5)
		view_h = vis.y / maxf(ct.get_scale().y, 0.0001)
	var wanted_h := TableSpace.floor_height(center)
	if not _cam_h_init or delta <= 0.0:
		_cam_h = wanted_h
		_cam_h_init = true
	else:
		_cam_h = lerpf(_cam_h, wanted_h, 1.0 - exp(-CAMERA_HEIGHT_SMOOTH * delta))
	var focus := TableSpace.to3(center, _cam_h)
	var tilt := deg_to_rad(CAMERA_TILT_DEG)
	var half_h := view_h * TableSpace.SCALE * 0.5
	var dist := half_h * cos(tilt) / tan(deg_to_rad(CAMERA_FOV_DEG) * 0.5)
	camera.position = focus + Vector3(0.0, dist * cos(tilt), dist * sin(tilt))
	camera.look_at(focus, Vector3(0.0, 0.0, -1.0))


# ------------------------------------------------------------------- projector -----


## Screen position (viewport logical px) of a table-space point at a height.
func project_point(p: Vector2, h: float = -1.0) -> Vector2:
	if camera == null:
		return p
	var hh := h if h >= 0.0 else TableSpace.floor_height(p)
	return camera.unproject_position(TableSpace.to3(p, hh))


## Screen position of a 2D node — a ball reports from its 3D body so a ramp ride lands right.
func project_node(node: Node2D) -> Vector2:
	if node is Ball:
		for bp in _balls:
			if is_instance_valid(bp) and bp.source == node and camera != null:
				return camera.unproject_position(bp.global_position)
	return project_point(node.global_position)
