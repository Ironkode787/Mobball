class_name ProgressionTable
extends TableSegment
## The machine. One inclined cabinet at real pinball scale (Layout), simulated in 3D by Jolt
## and dressed as the career it belongs to: the bare alley of Rank 0 grows the Block, the
## Club deck, the Docks, the Penthouse and City Hall as they are bought — every piece is
## registered under the Ledger id that owns it and stands up or goes dormant with
## `refresh_hardware()`.
##
## Contract with the flow lane (see TableAPI): properties `flipper_left/right`, `plunger`,
## `ball`, `auto_respawn`, `balls_served`, `pays_through_game`, `storefronts`, `docks`,
## `boss_sedan/boss_truck`; the signals below; and the methods under "flow API".

signal ball_spawned(ball: Ball)
signal ball_lost(ball: Ball)
signal laundromat_pass()
signal bribe_offered()
signal orbit_completed()
signal truck_route_completed()
signal rollover_rolled(index: int, was_lit: bool)
signal storefront_collected(id: StringName, amount: BigMoney)
signal staircase_climbed(speed: float)
signal roulette_landed(pocket: int, house: bool)
signal reels_state(cleared_columns: Array)
signal high_roller_held(steps: int)
signal backroom_entered()
signal deck_returned()
signal ball_searched(at: Vector3)
signal boss_hit(kind: StringName, hits_left: int, speed: float)
signal boss_shrugged(kind: StringName, speed: float)
signal boss_down(kind: StringName)
signal docks_entered()
signal container_stack_cleared(stack: int)
signal containers_state(cleared_stacks: Array)
signal crane_telegraph()
signal crane_pulled()
signal cargo_shipped(speed: float)
signal chair_taken(index: int)
signal chairs_completed()
signal sitdown_entered()
signal penthouse_entered(speed: float)
signal penthouse_returned()
signal dome_loop_completed(speed: float)
signal briefcase_collected()
signal briefcase_expired()

const BALL_SCENE := preload("res://game/core/ball.tscn")
const PLUNGER_STARTER_POWERS := [0.55, 0.58, 0.80]
const PLUNGER_STARTER_DEFAULT_BAND := 1
const PLUNGER_FIXED_POWER := 0.55
const MAGNET_MIN_GAP := DrainMagnet.TELEGRAPH + 0.5
const BALL_SEARCH_FLOOR_Z := 3.9        ## below this the flippers are the search
const SEARCH_BOX_Y := 2.2

var pays_through_game: bool = true
var debug_all_hardware: bool = false

var flipper_left: Flipper = null
var flipper_right: Flipper = null
var plunger: BandedPlunger = null
var ball: Ball = null
var auto_respawn: bool = true
var balls_served: int = 0

var spinner: Spinner = null
var wire_bank: TargetBank = null
var orbit: OrbitLane = null
var orbit_right: OrbitLane = null
var kickback: Kickback = null
var magnet: DrainMagnet = null
var director: DrainMagnet = null
var vans: FederalVans = null
var bribe_target: StandupTarget = null
var storefronts: Array[Storefront] = []
var rollovers: Array[Rollover] = []
var cop_targets: Array[StandupTarget] = []
var raid_active: bool = false
var federal_phase: int = 0
var briefcase: Briefcase = null
var boss_sedan: BossTarget = null
var boss_truck: BossTarget = null
var boss_goons: Array[StandupTarget] = []
var boss_door: TargetBank = null
var boss_active: bool = false
var club: ClubDeck = null
var docks: Docks = null
var penthouse: Penthouse = null
var city_hall: CityHall = null
var construction: BuildIn = null
var gate: OneWayGate = null

var _bumpers: Array[Bumper] = []
var _slings: Array[Slingshot] = []
var _pieces: Array[Dictionary] = []
var _forced: Dictionary = {}
var _lit_lane: int = -1
var _respawn_in: float = -1.0
var _still_for: float = 0.0
var _search_rng := RandomNumberGenerator.new()
var _case_rng := RandomNumberGenerator.new()
var _boss_meter_text: String = ""
var _boss_meter_fill: float = 0.0
var _built_once: Dictionary = {}
var _first_refresh: bool = true
var _lib: MaterialLib = null
var _lamps: Array[OmniLight3D] = []


func segment_id() -> StringName:
	return &"table_main"


func bounds() -> AABB:
	return AABB(Vector3(Layout.PLAY_LEFT - 0.2, -0.3, Layout.PLAY_TOP - 0.5),
			Vector3(Layout.PLAY_RIGHT - Layout.PLAY_LEFT + 0.4, 2.6, Layout.PLAY_BOTTOM - Layout.PLAY_TOP + 0.8))


func spawn_point() -> Vector3:
	return Layout.p3(Layout.SPAWN, Feel.BALL_RADIUS + 0.01)


func lane_box() -> AABB:
	return AABB(Vector3(Layout.DIVIDER_X + 0.02, -0.2, -4.4), Vector3(0.4, 1.0, 9.7))


## Plan-space anchors for the flow lane.
func socket(id: StringName) -> Vector2:
	match id:
		&"arch_top":
			return Vector2(0.0, Layout.PLAY_TOP + 0.4)
		&"left_channel":
			return Layout.ORBIT_L_ENTRY
		&"midfield":
			return Vector2(0.0, 0.6)
		&"drain":
			return Layout.CENTRE_DRAIN_AT
		&"club_deck":
			return Vector2((ClubDeck.DECK_LEFT + ClubDeck.DECK_RIGHT) * 0.5, ClubDeck.DECK_BOTTOM - 0.3)
		&"stair_mouth":
			return Layout.STAIR_MOUTH
		&"docks":
			return Docks.CRATES_ORIGIN
		&"penthouse":
			return Penthouse.TABLE_AT
		&"city_hall":
			return CityHall.DOME_AT
	return Vector2.ZERO


## Height of the floor a plan point stands on: the deck/room slabs or the felt.
func floor_height_at(p: Vector2) -> float:
	if club != null and club.is_hardware_active() and club.deck_rect().has_point(p):
		return ClubDeck.DECK_H
	if penthouse != null and penthouse.is_hardware_active() \
			and Rect2(Vector2(Penthouse.ROOM_LEFT, Penthouse.ROOM_TOP),
			Vector2(Penthouse.ROOM_RIGHT - Penthouse.ROOM_LEFT, Penthouse.ROOM_BOTTOM - Penthouse.ROOM_TOP)).has_point(p):
		return Penthouse.ROOM_H
	return 0.0


# ===================================================================== build =====


func _ready() -> void:
	rotation.x = deg_to_rad(Feel.PLAYFIELD_PITCH_DEG)
	_lib = MaterialLib.shared()
	_search_rng.seed = 0x5EA12C4
	_case_rng.seed = 0xB1EFCA5E
	_read_env_hook()
	_build_environment()
	_build_cabinet()
	_build_walls()
	_build_gate()
	_build_lanes()
	_build_top_lanes()
	_build_bumpers()
	_build_slings()
	_build_wire()
	_build_storefronts()
	_build_extras()
	_build_flippers()
	_build_bosses()
	_build_segments()
	_build_drain()
	_build_plunger()
	_build_construction()
	var dressing := TableDressing.new()
	dressing.name = "Dressing"
	add_child(dressing)
	dressing.build(self)
	Events.upgrade_purchased.connect(_on_upgrade_purchased)
	Events.session_booted.connect(refresh_hardware)
	refresh_hardware()


func _read_env_hook() -> void:
	if not ReleaseChannel.allow_development_hooks():
		return
	if OS.get_environment("KINGPIN_TABLE_DEBUG") == "1":
		debug_all_hardware = true
	var forced := OS.get_environment("KINGPIN_TABLE_HARDWARE")
	for id in forced.split(",", false):
		_forced[StringName(id.strip_edges())] = true


func _build_environment() -> void:
	var env_node := WorldEnvironment.new()
	env_node.name = "Environment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _lib.city_color(&"ink_glass", Feel.COL_INK).darkened(0.4)
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("2A2622")
	sky_mat.sky_horizon_color = Color("5A4A36")
	sky_mat.ground_horizon_color = Color("3A2C1E")
	sky_mat.ground_bottom_color = Color("100C08")
	sky_mat.sun_angle_max = 0.0
	sky_mat.sun_curve = 0.0
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
	env_node.environment = env
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.light_color = Color(1.0, 0.92, 0.80)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
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
	_lamp(Vector3(0.0, 2.4, 3.6), Color(1.0, 0.9, 0.75), 1.3, 6.5, "FlipperGI")
	_lamp(Vector3(0.0, 2.6, -2.6), Color(1.0, 0.88, 0.7), 0.9, 6.5, "UpperGI")


func _lamp(at: Vector3, color: Color, energy: float, range_m: float, p_name: String) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = p_name
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.position = at
	add_child(l)
	_lamps.append(l)
	return l


func _build_cabinet() -> void:
	var w := Layout.PLAY_RIGHT - Layout.PLAY_LEFT + Layout.OUTER_THICK
	var d := Layout.PLAY_BOTTOM - Layout.PLAY_TOP + Layout.OUTER_THICK
	var center_z := (Layout.PLAY_TOP + Layout.PLAY_BOTTOM) * 0.5
	# the felt
	var floor_body := WallBuilder.make_body("Floor", Feel.LAYER_WALLS,
			Feel.make_material(Feel.FELT_FRICTION, Feel.FELT_BOUNCE))
	add_child(floor_body)
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(w + 0.4, 0.2, d + 0.4)
	fs.shape = fb
	fs.position = Vector3(0.0, -0.1, center_z)
	floor_body.add_child(fs)
	var felt := PlaneMesh.new()
	felt.size = Vector2(w, d)
	felt.subdivide_depth = 8
	var fm := MeshInstance3D.new()
	fm.mesh = felt
	var street := ShaderMaterial.new()
	street.shader = load("res://game/table/look/playfield.gdshader")
	street.set_shader_parameter("field_size", Vector2(w, d))
	street.set_shader_parameter("mirror_x", Layout.MIRROR_X)
	if _lib.has_set("brick_pavement_02") and _lib.has_set("asphalt_02"):
		street.set_shader_parameter("textured", true)
		street.set_shader_parameter("stone_albedo", _lib.tex("brick_pavement_02", "diffuse", "2k"))
		street.set_shader_parameter("stone_normal", _lib.tex("brick_pavement_02", "nor_gl"))
		street.set_shader_parameter("stone_rough", _lib.tex("brick_pavement_02", "rough"))
		street.set_shader_parameter("alley_albedo", _lib.tex("asphalt_02", "diffuse"))
		street.set_shader_parameter("alley_normal", _lib.tex("asphalt_02", "nor_gl"))
		street.set_shader_parameter("alley_rough", _lib.tex("asphalt_02", "rough"))
	fm.material_override = street
	fm.position = Vector3(0.0, 0.0, center_z)
	fm.name = "Street"
	floor_body.add_child(fm)
	# shooter lane floor in wood
	var lane := PlaneMesh.new()
	lane.size = Vector2(Layout.PLAY_RIGHT - Layout.DIVIDER_X, Layout.LANE_FLOOR_Z - Layout.DIVIDER_TOP)
	var lm := MeshInstance3D.new()
	lm.mesh = lane
	lm.material_override = _lib.lane_wood(lane.size)
	lm.position = Vector3((Layout.DIVIDER_X + Layout.PLAY_RIGHT) * 0.5, 0.004, (Layout.DIVIDER_TOP + Layout.LANE_FLOOR_Z) * 0.5)
	floor_body.add_child(lm)
	# the glass: invisible ceiling so nothing ever leaves the cabinet
	var glass := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(w + 0.4, 0.1, d + 0.4)
	glass.shape = gb
	glass.position = Vector3(0.0, Layout.GLASS_HEIGHT + 0.05, center_z)
	floor_body.add_child(glass)
	# cabinet sides, front board, lockdown bar, backboard
	var st := MeshLib.begin()
	var side_h := Layout.CABINET_HEIGHT
	for sx in [Layout.PLAY_LEFT - Layout.OUTER_THICK - 0.06, Layout.PLAY_RIGHT + Layout.OUTER_THICK + 0.06]:
		MeshLib.box(st, Vector3(sx, side_h * 0.5 - 0.3, center_z), Vector3(0.12, side_h + 0.3, d + 0.5))
	MeshLib.box(st, Vector3(0.0, side_h * 0.5 - 0.3, Layout.PLAY_BOTTOM + 0.25), Vector3(w + 0.5, side_h + 0.3, 0.3))
	MeshLib.box(st, Vector3(0.0, 1.2, Layout.PLAY_TOP - 0.28), Vector3(w + 0.5, 3.0, 0.3))
	var cab := MeshInstance3D.new()
	cab.mesh = MeshLib.finish(st, _lib.wood_dark())
	cab.name = "Cabinet"
	add_child(cab)
	var bar := MeshLib.begin()
	MeshLib.box(bar, Vector3(0.0, side_h + 0.02, Layout.PLAY_BOTTOM + 0.25), Vector3(w + 0.5, 0.06, 0.34))
	for sx in [Layout.PLAY_LEFT - Layout.OUTER_THICK - 0.06, Layout.PLAY_RIGHT + Layout.OUTER_THICK + 0.06]:
		MeshLib.box(bar, Vector3(sx, side_h + 0.01, center_z), Vector3(0.14, 0.03, d + 0.5))
	var bm := MeshInstance3D.new()
	bm.mesh = MeshLib.finish(bar, _lib.brass())
	bm.name = "Rails"
	add_child(bm)
	# backglass
	var tex: Texture2D = null
	if Presentation != null and Presentation.art != null:
		tex = Presentation.art.resolve(&"table.backglass.eastport", null, false)
	if tex != null:
		var quad := PlaneMesh.new()
		quad.size = Vector2(w * 0.92, w * 0.92 * float(tex.get_height()) / float(tex.get_width()))
		quad.orientation = PlaneMesh.FACE_Z
		var gm := _lib.art(tex, 0.0)
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color(1.1, 1.1, 1.1)
		gm.cull_mode = BaseMaterial3D.CULL_BACK
		var gmi := MeshInstance3D.new()
		gmi.mesh = quad
		gmi.material_override = gm
		gmi.position = Vector3(0.0, 1.4 + quad.size.y * 0.5, Layout.PLAY_TOP - 0.12)
		gmi.name = "Backglass"
		add_child(gmi)
	# apron cards over the drain
	var apron := MeshLib.begin()
	for sx in [Layout.MIRROR_X - 1.6, Layout.MIRROR_X + 1.6]:
		MeshLib.box(apron, Vector3(sx, 0.05, 4.95), Vector3(0.8, 0.08, 0.6))
	var am := MeshInstance3D.new()
	am.mesh = MeshLib.finish(apron, _lib.paper())
	am.name = "ApronCards"
	add_child(am)
	# the storm grate under the flippers
	var grate := PlaneMesh.new()
	grate.size = Vector2(Layout.CENTRE_DRAIN_SIZE.x, Layout.CENTRE_DRAIN_SIZE.y)
	var grate_mat := StandardMaterial3D.new()
	grate_mat.albedo_texture = _lib.grate_texture()
	grate_mat.emission_enabled = true
	grate_mat.emission_texture = _lib.grate_texture()
	grate_mat.emission = Color.WHITE
	grate_mat.emission_energy_multiplier = 0.8
	var gr := MeshInstance3D.new()
	gr.mesh = grate
	gr.material_override = grate_mat
	gr.position = Layout.p3(Layout.CENTRE_DRAIN_AT + Vector2(0.0, 0.1), 0.005)
	gr.name = "StormGrate"
	add_child(gr)


func _build_walls() -> void:
	var body := WallBuilder.make_body("Walls")
	add_child(body)
	var walls := WallBuilder.new(body, Layout.WALL_HEIGHT * 1.6)
	var t := Layout.OUTER_THICK
	# outer boundary: left side, the arch, right side, bottom
	walls.bar(Vector2(Layout.PLAY_LEFT, Layout.PLAY_BOTTOM), Vector2(Layout.PLAY_LEFT, Layout.ARCH_CENTER.y), t)
	walls.arc(Layout.ARCH_CENTER, Layout.ARCH_RADIUS, 180.0, 360.0, 48, t)
	walls.bar(Vector2(Layout.PLAY_RIGHT, Layout.ARCH_CENTER.y), Vector2(Layout.PLAY_RIGHT, Layout.PLAY_BOTTOM), t)
	walls.bar(Vector2(Layout.PLAY_LEFT, Layout.PLAY_BOTTOM), Vector2(Layout.PLAY_RIGHT, Layout.PLAY_BOTTOM), t)
	# shooter lane divider and floor stop
	walls.bar(Vector2(Layout.DIVIDER_X, Layout.DIVIDER_TOP), Vector2(Layout.DIVIDER_X, Layout.DIVIDER_BOTTOM),
			Layout.DIVIDER_THICK, Layout.WALL_HEIGHT)
	walls.bar(Vector2(Layout.DIVIDER_X, Layout.LANE_FLOOR_Z), Vector2(Layout.PLAY_RIGHT, Layout.LANE_FLOOR_Z),
			Layout.DIVIDER_THICK, Layout.WALL_HEIGHT)
	# the inlane return sweeps and the lane-return deflectors: starter furniture
	for s: float in [1.0, -1.0]:
		walls.bar(Vector2(Layout.inlane_guide_x(s), Layout.INLANE_GUIDE_BOTTOM),
				Layout.mx(Layout.INLANE_END, s), Layout.GUIDE_THICK, Layout.GUIDE_HEIGHT)
	walls.bar(Layout.LANE_RETURN_R[0], Layout.LANE_RETURN_R[1], Layout.GUIDE_THICK, Layout.GUIDE_HEIGHT)
	walls.bar(Layout.LANE_RETURN_L[0], Layout.LANE_RETURN_L[1], Layout.GUIDE_THICK, Layout.GUIDE_HEIGHT)
	walls.build_mesh(_lib.wood(), _lib.brass())

	# Guard Rails: the vertical outlane guards are an upgrade (docs/02 §2 R0)
	var guides := WallPiece.new(Layout.GUIDE_HEIGHT, 0.0, _lib.brass_dark())
	guides.name = "InlaneGuides"
	add_child(guides)
	for s: float in [1.0, -1.0]:
		guides.bar(Vector2(Layout.inlane_guide_x(s), Layout.INLANE_GUIDE_TOP),
				Vector2(Layout.inlane_guide_x(s), Layout.INLANE_GUIDE_BOTTOM), Layout.GUIDE_THICK)
	_register([&"inlane_guides"], guides)


func _build_gate() -> void:
	gate = OneWayGate.new()
	gate.name = "ShooterGate"
	gate.configure(&"shooter_gate", Vector2(Layout.DIVIDER_X, Layout.GATE_TOP),
			Vector2(Layout.DIVIDER_X, Layout.GATE_BOTTOM), 0.04, Vector2(1.0, 0.0))
	add_child(gate)


func _build_lanes() -> void:
	var guide := WallPiece.new(Layout.GUIDE_HEIGHT, 0.0, _lib.brass_dark())
	guide.name = "NumbersLaneGuide"
	add_child(guide)
	guide.bar(Vector2(Layout.LANE_GUIDE_L_X, Layout.RING_CENTER.y), Vector2(Layout.LANE_GUIDE_L_X, Layout.LANE_GUIDE_L_BOTTOM), Layout.GUIDE_THICK)
	_register([&"spinner_numbers", &"orbit_left"], guide)

	var arc := WallPiece.new(Layout.GUIDE_HEIGHT, 0.0, _lib.brass_dark())
	arc.name = "GetawayArc"
	add_child(arc)
	arc.arc(Layout.RING_CENTER, Layout.RING_RADIUS, Layout.RING_LEFT_FROM_DEG, Layout.RING_LEFT_TO_DEG, 16, Layout.GUIDE_THICK)
	_register([&"orbit_left"], arc)

	spinner = Spinner.new()
	spinner.name = "Spinner"
	spinner.configure(&"spinner_numbers", Layout.SPINNER_AT, Layout.LANE_WIDTH_L)
	add_child(spinner)
	_register([&"spinner_numbers"], spinner)

	orbit = OrbitLane.new()
	orbit.name = "OrbitLeft"
	add_child(orbit)
	orbit.configure(&"orbit_left", Layout.ORBIT_L_ENTRY, Vector2(Layout.LANE_WIDTH_L, 0.25),
			Layout.ring_point(Layout.ORBIT_L_EXIT_DEG, Layout.CHANNEL_MID_RADIUS), 0.2)
	orbit.orbit_completed.connect(func() -> void: orbit_completed.emit())
	_register([&"orbit_left"], orbit)

	# THE TRUCK ROUTE: the right lane guide and the ring's right arm
	var guide_r := WallPiece.new(Layout.GUIDE_HEIGHT, 0.0, _lib.brass_dark())
	guide_r.name = "TruckRouteGuide"
	add_child(guide_r)
	guide_r.bar(Vector2(Layout.LANE_GUIDE_R_X, Layout.RING_CENTER.y), Vector2(Layout.LANE_GUIDE_R_X, Layout.LANE_GUIDE_R_BOTTOM), Layout.GUIDE_THICK)
	_register([&"orbit_right"], guide_r)
	var arc_r := WallPiece.new(Layout.GUIDE_HEIGHT, 0.0, _lib.brass_dark())
	arc_r.name = "TruckRouteArc"
	add_child(arc_r)
	arc_r.arc(Layout.RING_CENTER, Layout.RING_RADIUS, Layout.RING_RIGHT_FROM_DEG, Layout.RING_RIGHT_TO_DEG, 16, Layout.GUIDE_THICK)
	_register([&"orbit_right"], arc_r)
	orbit_right = OrbitLane.new()
	orbit_right.name = "OrbitRight"
	add_child(orbit_right)
	orbit_right.configure(&"orbit_right", Layout.ORBIT_R_ENTRY, Vector2(0.36, 0.25),
			Layout.ring_point(Layout.ORBIT_R_EXIT_DEG, Layout.CHANNEL_MID_RADIUS), 0.2)
	orbit_right.orbit_completed.connect(func() -> void:
		orbit_completed.emit()
		truck_route_completed.emit())
	_register([&"orbit_right"], orbit_right)


func _build_top_lanes() -> void:
	var posts := WallPiece.new(Layout.GUIDE_HEIGHT, 0.0, _lib.brass_dark())
	posts.name = "TopLanePosts"
	add_child(posts)
	for i in range(Layout.TOP_POST_DEG.size()):
		posts.bar(Layout.ring_point(Layout.TOP_POST_DEG[i]), Layout.TOP_POST_BOTTOM[i], Layout.GUIDE_THICK)
	_register([&"rollovers"], posts)
	for i in range(Layout.ROLLOVER_AT.size()):
		var r := Rollover.new()
		r.name = "Rollover%d" % (i + 1)
		r.configure(StringName("rollover_%d" % (i + 1)), i, Layout.ROLLOVER_AT[i])
		add_child(r)
		r.rolled.connect(_on_rollover)
		rollovers.append(r)
		_register([&"rollovers"], r)


func _build_bumpers() -> void:
	for i in range(Layout.BUMPER_AT.size()):
		var b := Bumper.new()
		b.id = StringName("bumper_%d" % (i + 1))
		b.group = TableScore.GROUP_BUMPERS
		b.value = int(TableScore.BUMPER)
		b.position = Layout.p3(Layout.BUMPER_AT[i])
		b.size_scale = Layout.BUMPER_SCALE[i]
		b.name = "Bumper%d" % (i + 1)
		add_child(b)
		_bumpers.append(b)
		if i > 0:
			_register([b.id], b)


func _build_slings() -> void:
	for s: float in [1.0, -1.0]:
		var sl := Slingshot.new()
		sl.passive_when_inactive = true
		var id := &"sling_r" if s > 0.0 else &"sling_l"
		sl.configure(id, Layout.mx(Layout.SLING_OUTER_BOTTOM, s), Layout.mx(Layout.SLING_INNER, s),
				Layout.mx(Layout.SLING_OUTER_TOP, s))
		sl.group = TableScore.GROUP_SLINGS
		sl.value = int(TableScore.SLING)
		sl.name = "SlingR" if s > 0.0 else "SlingL"
		add_child(sl)
		_slings.append(sl)
		_register([&"slingshots"], sl)


func _build_wire() -> void:
	wire_bank = TargetBank.new()
	wire_bank.name = "WireBank"
	wire_bank.id = &"wire_bank"
	add_child(wire_bank)
	for i in range(Layout.WIRE_AT.size()):
		var t := StandupTarget.new()
		t.name = "Payphone%d" % (i + 1)
		t.configure(StringName("wire_%d" % (i + 1)), Layout.WIRE_AT[i], Layout.WIRE_FACE, Layout.WIRE_LENGTHS[i])
		wire_bank.add_target(t)
	_register([&"wire_bank"], wire_bank)


func _build_storefronts() -> void:
	for i in range(Layout.STOREFRONT_AT.size()):
		var s := Storefront.new()
		s.name = "Storefront%d" % (i + 1)
		s.configure(Layout.STOREFRONT_IDS[i], Layout.STOREFRONT_AT[i], Layout.STOREFRONT_FACING[i],
				Layout.STOREFRONT_RAKE_DEG[i], Layout.STOREFRONT_SIGNS[i])
		add_child(s)
		s.collected.connect(_on_storefront_collected)
		s.washed.connect(_on_laundromat_wash)
		storefronts.append(s)
		if Layout.STOREFRONT_IDS[i] == &"storefront_laundromat":
			_register([&"storefront_laundromat", &"laundromat_loop"], s)
		else:
			_register([Layout.STOREFRONT_IDS[i]], s)


func _build_extras() -> void:
	bribe_target = StandupTarget.new()
	bribe_target.name = "BribeTarget"
	bribe_target.configure(&"bribe_target", Layout.BRIBE_AT, Layout.BRIBE_FACE, Layout.BRIBE_LENGTH)
	add_child(bribe_target)
	bribe_target.struck.connect(_on_bribe_struck)
	_register([&"bribe_target"], bribe_target)

	for i in range(Layout.COP_AT.size()):
		var c := StandupTarget.new()
		c.name = "Cop%d" % (i + 1)
		c.lamp_color = Feel.COL_COP
		c.configure(StringName("cop_%d" % (i + 1)), Layout.COP_AT[i],
				Vector2(0.0, 1.0).rotated(deg_to_rad(Layout.COP_RAKE_DEG[i])), Layout.TARGET_LENGTH)
		add_child(c)
		c.struck.connect(_on_cop_struck)
		cop_targets.append(c)
		c.set_hardware_active(false)

	kickback = Kickback.new()
	kickback.name = "KickbackLeft"
	kickback.configure(&"kickback_left", Layout.KICKBACK_AT, Layout.KICKBACK_SIZE, Vector2(0.15, -1.0))
	add_child(kickback)
	_register([&"kickback_left"], kickback)

	magnet = DrainMagnet.new()
	magnet.name = "CaptainsMagnet"
	magnet.position = Layout.p3(Layout.MAGNET_AT)
	magnet.drain_point = Vector2(0.0, Layout.DRAIN_Z + 0.2)
	add_child(magnet)

	director = DrainMagnet.new()
	director.name = "DirectorsMagnet"
	director.position = Layout.p3(Layout.DIRECTOR_AT)
	director.drain_point = Vector2(0.0, Layout.DRAIN_Z + 0.2)
	director.self_driven = true
	add_child(director)

	vans = FederalVans.new()
	vans.name = "FederalVans"
	add_child(vans)

	briefcase = Briefcase.new()
	briefcase.name = "Briefcase"
	add_child(briefcase)
	briefcase.collected.connect(_on_briefcase_collected)
	briefcase.expired.connect(func() -> void: briefcase_expired.emit())


func _build_flippers() -> void:
	flipper_left = Flipper.new()
	flipper_left.side = &"left"
	flipper_left.name = "FlipperLeft"
	flipper_left.position = Layout.p3(Layout.FLIPPER_PIVOT_L)
	add_child(flipper_left)
	flipper_right = Flipper.new()
	flipper_right.side = &"right"
	flipper_right.name = "FlipperRight"
	flipper_right.position = Layout.p3(Layout.FLIPPER_PIVOT_R)
	add_child(flipper_right)


func _build_bosses() -> void:
	boss_sedan = BossTarget.new()
	boss_sedan.name = "BossSedan"
	boss_sedan.kind = &"sedan"
	boss_sedan.color = Feel.COL_INK.lightened(0.16)
	add_child(boss_sedan)
	boss_sedan.size_to(Layout.SEDAN_LENGTH, Layout.SEDAN_THICK)
	boss_sedan.set_path(PackedVector2Array([
		Vector2(Layout.SEDAN_RAIL_FROM_X, Layout.SEDAN_RAIL_Z), Vector2(Layout.SEDAN_RAIL_TO_X, Layout.SEDAN_RAIL_Z),
	]))
	_wire_boss_target(boss_sedan)

	boss_truck = BossTarget.new()
	boss_truck.name = "BossTruck"
	boss_truck.kind = &"truck"
	boss_truck.color = Feel.COL_NEWSPRINT.darkened(0.18)
	add_child(boss_truck)
	boss_truck.size_to(Layout.TRUCK_LENGTH, Layout.TRUCK_THICK)
	boss_truck.set_path(_truck_path())
	_wire_boss_target(boss_truck)

	for i in range(Layout.GOON_AT.size()):
		var g := StandupTarget.new()
		g.name = "Goon%d" % (i + 1)
		g.lamp_color = Feel.COL_DIRTY
		g.configure(StringName("boss_goon_%d" % (i + 1)), Layout.GOON_AT[i],
				Vector2(0.0, 1.0).rotated(deg_to_rad(Layout.GOON_RAKE_DEG[i])), Layout.TARGET_LENGTH)
		add_child(g)
		g.struck.connect(_on_goon_struck)
		boss_goons.append(g)
		g.set_hardware_active(false)

	boss_door = TargetBank.new()
	boss_door.name = "ButcherDoor"
	boss_door.id = &"boss_door"
	boss_door.group = TableScore.GROUP_BUMPERS
	boss_door.target_value = 0.0
	boss_door.complete_value = 0.0
	boss_door.reset_seconds = 999.0
	add_child(boss_door)
	for row in range(2):
		var zs := Layout.DOOR_FRONT_Z if row == 0 else Layout.DOOR_BACK_Z
		var xs := Layout.DOOR_FRONT_X if row == 0 else Layout.DOOR_BACK_X
		for i in range(xs.size()):
			var t := StandupTarget.new()
			t.name = "Door%d%d" % [row + 1, i + 1]
			t.lamp_color = Feel.COL_DIRTY
			t.configure(StringName("boss_door_%d%d" % [row + 1, i + 1]), Vector2(xs[i], zs),
					Vector2(0.0, 1.0).rotated(deg_to_rad(Layout.DOOR_RAKE_DEG * (1.0 if i % 2 == 0 else -1.0))),
					Layout.TARGET_LENGTH * 0.8)
			boss_door.add_target(t)
	boss_door.target_struck.connect(func(_i: int) -> void:
		boss_hit.emit(&"door", boss_door_panels_left(), 0.0)
		if boss_door_panels_left() <= 0:
			boss_down.emit(&"door"))
	boss_door.set_hardware_active(false)


func _wire_boss_target(t: BossTarget) -> void:
	t.set_hardware_active(false)
	t.struck.connect(func(kind: StringName, left: int, speed: float) -> void: boss_hit.emit(kind, left, speed))
	t.shrugged.connect(func(kind: StringName, speed: float) -> void: boss_shrugged.emit(kind, speed))
	t.broken.connect(func(kind: StringName) -> void: boss_down.emit(kind))


## The truck's beat: the orbit channel, sampled so the body lies along the arch.
func _truck_path() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(15):
		var deg := lerpf(200.0, 340.0, float(i) / 14.0)
		pts.append(Layout.ring_point(deg, Layout.CHANNEL_MID_RADIUS))
	return pts


func _build_segments() -> void:
	club = ClubDeck.new()
	club.name = "Club"
	add_child(club)
	club.bind_flippers(flipper_left, flipper_right)
	club.staircase_climbed.connect(func(speed: float) -> void: staircase_climbed.emit(speed))
	club.roulette_landed.connect(func(p: int, h: bool) -> void: roulette_landed.emit(p, h))
	club.reels_state.connect(func(cols: Array) -> void: reels_state.emit(cols))
	club.high_roller_held.connect(func(steps: int) -> void: high_roller_held.emit(steps))
	club.backroom_entered.connect(func() -> void: backroom_entered.emit())
	club.returned_home.connect(func(_at: Vector2) -> void: deck_returned.emit())
	_register([ClubDeck.ID_DECK], club)
	for piece: Dictionary in club.pieces():
		_register(piece["ids"], piece["node"], ClubDeck.ID_DECK)

	docks = Docks.new()
	docks.name = "Docks"
	add_child(docks)
	docks.docks_entered.connect(func() -> void: docks_entered.emit())
	docks.stack_cleared.connect(func(s: int) -> void: container_stack_cleared.emit(s))
	docks.containers_state.connect(func(c: Array) -> void: containers_state.emit(c))
	docks.crane_telegraph.connect(func() -> void: crane_telegraph.emit())
	docks.crane_pulled.connect(func() -> void: crane_pulled.emit())
	docks.cargo_shipped.connect(func(speed: float) -> void: cargo_shipped.emit(speed))
	docks.pier_fall.connect(func(b: Ball) -> void: _lose_ball(b, &"pier_splash"))
	_register([Docks.ID_DOCKS], docks)
	for piece: Dictionary in docks.pieces():
		_register(piece["ids"], piece["node"], Docks.ID_DOCKS)

	penthouse = Penthouse.new()
	penthouse.name = "Penthouse"
	add_child(penthouse)
	penthouse.chair_taken.connect(func(i: int) -> void: chair_taken.emit(i))
	penthouse.chairs_completed.connect(func() -> void: chairs_completed.emit())
	penthouse.sitdown_entered.connect(func() -> void: sitdown_entered.emit())
	penthouse.penthouse_entered.connect(func(speed: float) -> void: penthouse_entered.emit(speed))
	penthouse.penthouse_returned.connect(func() -> void: penthouse_returned.emit())
	_register([Penthouse.ID_PENTHOUSE], penthouse, ClubDeck.ID_DECK)
	for piece: Dictionary in penthouse.pieces():
		_register(piece["ids"], piece["node"], Penthouse.ID_PENTHOUSE)

	city_hall = CityHall.new()
	city_hall.name = "CityHall"
	add_child(city_hall)
	city_hall.dome_loop_completed.connect(func(speed: float) -> void: dome_loop_completed.emit(speed))
	_register([CityHall.ID_CITY_HALL], city_hall, Penthouse.ID_PENTHOUSE)
	_register([CityHall.ID_LOOP], city_hall.loop, CityHall.ID_CITY_HALL)


func _build_drain() -> void:
	var area := Area3D.new()
	area.name = "Drain"
	area.collision_layer = Feel.LAYER_ZONES
	area.collision_mask = Feel.LAYER_BALL
	area.monitorable = false
	_drain_shape(area, Layout.p3(Layout.CENTRE_DRAIN_AT, 0.25), Vector3(Layout.CENTRE_DRAIN_SIZE.x, 0.5, Layout.CENTRE_DRAIN_SIZE.y))
	for s: float in [1.0, -1.0]:
		var x0: float = Layout.inlane_guide_x(s) + s * Layout.GUIDE_THICK
		var x1: float = (Layout.DIVIDER_X - Layout.DIVIDER_THICK) if s > 0.0 \
				else (Layout.PLAY_LEFT + Layout.OUTER_THICK * 0.5)
		var z0 := Layout.OUTLANE_DRAIN_Z + 0.3
		var z1 := Layout.DRAIN_Z
		_drain_shape(area, Vector3((x0 + x1) * 0.5, 0.25, (z0 + z1) * 0.5), Vector3(absf(x1 - x0), 0.5, z1 - z0))
	# cabinet safety: anything below the felt or past the lip is gone
	_drain_shape(area, Vector3(0.0, 0.25, Layout.DRAIN_Z + 0.35), Vector3(5.6, 0.5, 0.5))
	_drain_shape(area, Vector3(0.0, -1.2, 0.0), Vector3(7.0, 0.6, 13.0))
	add_child(area)
	area.body_entered.connect(func(body: Node3D) -> void: _on_drain_entered(body))


func _drain_shape(area: Area3D, at: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = at
	area.add_child(cs)


func _build_plunger() -> void:
	plunger = BandedPlunger.new()
	plunger.name = "Plunger"
	plunger.lane_box = lane_box()
	plunger.lane_dir = Vector3(0.0, 0.0, -1.0)
	plunger.starter_powers = PLUNGER_STARTER_POWERS
	plunger.starter_band = PLUNGER_STARTER_DEFAULT_BAND
	add_child(plunger)
	# the rod, for the look
	var rod := Node3D.new()
	rod.name = "PlungerRod"
	var lane_x := (Layout.DIVIDER_X + Layout.PLAY_RIGHT) * 0.5
	rod.position = Vector3(lane_x, 0.0, Layout.LANE_FLOOR_Z + 0.1)
	add_child(rod)
	var housing := CylinderMesh.new()
	housing.top_radius = 0.09
	housing.bottom_radius = 0.09
	housing.height = 0.3
	var hm := MeshInstance3D.new()
	hm.mesh = housing
	hm.material_override = _lib.brass_dark()
	hm.rotation.x = PI * 0.5
	hm.position = Vector3(0.0, Feel.BALL_RADIUS, 0.25)
	rod.add_child(hm)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.035
	shaft.bottom_radius = 0.035
	shaft.height = 0.8
	var sm := MeshInstance3D.new()
	sm.mesh = shaft
	sm.material_override = _lib.steel()
	sm.rotation.x = PI * 0.5
	sm.position = Vector3(0.0, Feel.BALL_RADIUS, 0.5)
	rod.add_child(sm)
	var knob := SphereMesh.new()
	knob.radius = 0.1
	knob.height = 0.2
	var km := MeshInstance3D.new()
	km.mesh = knob
	km.material_override = _lib.plastic(Color("7A1E1E"), 0.4)
	km.position = Vector3(0.0, Feel.BALL_RADIUS, 0.95)
	rod.add_child(km)


func _build_construction() -> void:
	construction = BuildIn.new()
	construction.name = "Construction"
	construction.enabled = DisplayServer.get_name() != "headless" \
			and (not ReleaseChannel.allow_development_hooks() \
			or OS.get_environment("KINGPIN_NO_BUILD_ANIM") != "1")
	add_child(construction)


# ================================================================= unlocking =====


func _register(ids: Array, node: Node, needs: StringName = &"") -> void:
	var typed: Array[StringName] = []
	for id: Variant in ids:
		typed.append(StringName(id))
	_pieces.append({"ids": typed, "node": node, "needs": needs})


func hardware_unlocked(id: StringName) -> bool:
	if debug_all_hardware:
		return true
	if _forced.has(id):
		return true
	if Game == null or Game.stats == null:
		return false
	if id == &"bribe_target":
		return Game.stats.hardware_unlocked(id) or Game.stats.bribe_unlocked()
	return Game.stats.hardware_unlocked(id)


func _needs_met(id: StringName, depth: int = 0) -> bool:
	if id == &"" or depth > 4:
		return true
	if not hardware_unlocked(id):
		return false
	for piece: Dictionary in _pieces:
		var ids: Array[StringName] = piece["ids"]
		if ids.has(id):
			return _needs_met(StringName(piece.get("needs", &"")), depth + 1)
	return true


func hardware_present(id: StringName) -> bool:
	if id == &"slingshots":
		for sl: Slingshot in _slings:
			if sl.is_powered():
				return true
		return false
	var found := false
	for piece: Dictionary in _pieces:
		var ids: Array[StringName] = piece["ids"]
		if not ids.has(id):
			continue
		found = true
		if not (piece["node"] as Node3D).visible:
			return false
	return found


func hardware_pieces() -> Array[Dictionary]:
	return _pieces.duplicate()


func hardware_node(id: StringName) -> Node:
	for piece: Dictionary in _pieces:
		var ids: Array[StringName] = piece["ids"]
		if ids.has(id):
			return piece["node"]
	return null


func hardware_piece_active(piece: Dictionary) -> bool:
	if not _needs_met(StringName(piece.get("needs", &""))):
		return false
	for id: StringName in piece["ids"]:
		if hardware_unlocked(id):
			return true
	return false


func force_hardware(ids: Array, on: bool = true) -> void:
	for id: Variant in ids:
		if on:
			_forced[StringName(id)] = true
		else:
			_forced.erase(StringName(id))
	refresh_hardware()


func hardware_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for piece: Dictionary in _pieces:
		for id: StringName in piece["ids"]:
			if not out.has(id):
				out.append(id)
	return out


func refresh_hardware() -> void:
	for piece: Dictionary in _pieces:
		var node: Node3D = piece["node"]
		var live := hardware_piece_active(piece)
		Dormant.apply(node, live)
		if live == _built_once.has(node):
			continue
		if live:
			_built_once[node] = true
			if construction != null and not _first_refresh:
				construction.start(node)
		else:
			_built_once.erase(node)
			if construction != null:
				construction.cancel(node)
	_first_refresh = false
	if club != null:
		club.set_flippers_live(hardware_unlocked(ClubDeck.ID_DECK) and hardware_unlocked(ClubDeck.ID_FLIPPERS))
	for s in storefronts:
		s.bank_enabled = hardware_unlocked(s.id)
		s.wash_enabled = s.id == &"storefront_laundromat" and hardware_unlocked(&"laundromat_loop")
		s.apply_build()
	var power := 1.0
	if Game != null and Game.stats != null:
		power = Game.stats.flipper_power()
	for f: Flipper in [flipper_left, flipper_right]:
		if f != null:
			f.power_scale = power
	if plunger != null:
		plunger.bands_enabled = debug_all_hardware \
				or (Game != null and Game.stats != null and Game.stats.flag(&"plunger_bands"))


func _on_upgrade_purchased(_id: String, _level: int) -> void:
	refresh_hardware()


# ================================================================== flow API =====


func set_lit_rollover(index: int) -> void:
	_lit_lane = index
	for i in range(rollovers.size()):
		rollovers[i].set_lit(i == index)


func lit_rollover() -> int:
	return _lit_lane


func rollover_count() -> int:
	return rollovers.size()


func set_raid_active(active: bool) -> void:
	if raid_active == active:
		return
	raid_active = active
	_apply_raid_hardware()


func set_federal_raid(phase: int) -> void:
	var want := clampi(phase, 0, 3)
	if federal_phase == want:
		return
	var was := federal_phase
	federal_phase = want
	_apply_raid_hardware()
	vans.set_active(want >= 2)
	if want >= 3:
		if not director.active:
			director.set_active(true)
			director.reschedule(DrainMagnet.PERIOD * 0.5)
	else:
		director.set_active(false)
	if was == 0 and want > 0:
		AudioDirector.play(&"raid_start")


func _apply_raid_hardware() -> void:
	var on := raid_active or federal_phase >= 1
	for c in cop_targets:
		c.set_hardware_active(on)
		c.set_marked(false)
	magnet.set_active(on)
	if not on:
		set_raid_speed(1.0)


## A fresh officer where the flow asks for one (the M1 raid placed cops one by one).
func spawn_cop_target() -> void:
	for c in cop_targets:
		if not c.is_hardware_active():
			c.set_hardware_active(true)
			c.set_marked(false)
			return


func _keep_magnets_apart() -> void:
	if director == null or not director.active or not magnet.active:
		return
	var winding := magnet if magnet.is_telegraphing() else director
	var waiting := director if winding == magnet else magnet
	if not winding.is_telegraphing():
		return
	var gap := minf(MAGNET_MIN_GAP, DrainMagnet.PERIOD / maxf(waiting.rate, 0.25) * 0.45)
	if waiting.time_to_pull() < winding.time_to_pull() + gap:
		waiting.reschedule(winding.time_to_pull() + gap)


func magnet_pull() -> void:
	magnet.pull(ball)


func set_raid_speed(scale: float) -> void:
	var rate := clampf(scale, 0.25, 4.0)
	if magnet != null:
		magnet.rate = rate
	if director != null:
		director.rate = rate


func spawn_briefcase(at: Vector2 = Vector2.ZERO) -> void:
	if briefcase == null or briefcase.is_live():
		return
	var spot := at
	if spot == Vector2.ZERO:
		var open: Array[Vector2] = []
		for candidate: Vector2 in Layout.BRIEFCASE_SPOTS:
			if _spot_open(candidate):
				open.append(candidate)
		if open.is_empty():
			return
		spot = open[_case_rng.randi_range(0, open.size() - 1)]
	briefcase.drop_at(spot)


func briefcase_live() -> bool:
	return briefcase != null and briefcase.is_live()


func briefcase_at() -> Vector2:
	return Layout.plan(briefcase.position) if briefcase_live() else Vector2.ZERO


func _spot_open(at: Vector2) -> bool:
	for b in Balls.live():
		if is_instance_valid(b) and Layout.plan(b.table_position()).distance_to(at) < Layout.BRIEFCASE_CLEAR:
			return false
	for t: StandupTarget in cop_targets + boss_goons:
		if t.visible and Layout.plan(t.position).distance_to(at) < Layout.BRIEFCASE_CLEAR:
			return false
	if boss_door != null and boss_door.visible:
		for t: StandupTarget in boss_door.targets():
			if t.visible and Layout.plan(t.position).distance_to(at) < Layout.BRIEFCASE_CLEAR:
				return false
	for v: BossTarget in [boss_sedan, boss_truck]:
		if v != null and v.visible and Layout.plan(v.position).distance_to(at) < Layout.BRIEFCASE_CLEAR_VEHICLE:
			return false
	return true


func _on_briefcase_collected(_ball_hit: Ball) -> void:
	briefcase_collected.emit()


func clear_boss() -> void:
	boss_active = false
	for t: BossTarget in [boss_sedan, boss_truck]:
		if t != null:
			t.set_hardware_active(false)
			t.arm(0)
	set_boss_goons(false)
	set_boss_door(false)
	set_boss_meter("", 0.0)


func set_boss_target(kind: StringName, mode: StringName, hits: int = 0, speed_gate: float = 0.0) -> void:
	var t: BossTarget = boss_sedan if kind == &"sedan" else boss_truck
	if t == null:
		return
	if mode == &"off":
		t.set_hardware_active(false)
		t.arm(0)
		return
	boss_active = true
	t.arm(hits, speed_gate)
	if mode == &"park":
		t.park_at(Layout.SEDAN_PARK if kind == &"sedan" else Layout.TRUCK_PARK)
	else:
		t.set_path(PackedVector2Array([
			Vector2(Layout.SEDAN_RAIL_FROM_X, Layout.SEDAN_RAIL_Z), Vector2(Layout.SEDAN_RAIL_TO_X, Layout.SEDAN_RAIL_Z),
		]) if kind == &"sedan" else _truck_path())
		t.set_moving(true)
	t.set_hardware_active(true)


func set_boss_goons(on: bool) -> void:
	if on:
		boss_active = true
	for g in boss_goons:
		g.set_marked(false)
		g.set_hardware_active(on)


func boss_goons_standing() -> int:
	var n := 0
	for g in boss_goons:
		if g.visible and not g.marked:
			n += 1
	return n


func set_boss_door(on: bool) -> void:
	if boss_door == null:
		return
	if on:
		boss_active = true
		boss_door.reset_now()
	boss_door.set_hardware_active(on)


func boss_door_panels_left() -> int:
	if boss_door == null:
		return 0
	return boss_door.targets().size() - boss_door.marked_count()


func set_boss_meter(text: String, fill: float) -> void:
	_boss_meter_text = text
	_boss_meter_fill = clampf(fill, 0.0, 1.0)


func boss_meter() -> Dictionary:
	return {"text": _boss_meter_text, "fill": _boss_meter_fill}


func _on_goon_struck(target: StandupTarget, _ball_hit: Ball) -> void:
	if target.marked:
		return
	target.set_marked(true)
	AudioDirector.play(&"drop_clack")
	boss_hit.emit(&"goon", boss_goons_standing(), 0.0)
	if boss_goons_standing() <= 0:
		boss_down.emit(&"goon")


func auto_collect_one() -> StringName:
	for s in storefronts:
		if s.visible and s.is_open():
			if s.collect_now(ball).is_positive():
				return s.id
	return &""


func storefront_armed() -> bool:
	var any := false
	for s in storefronts:
		if not s.visible:
			continue
		any = true
		if s.state_name() != &"cooldown":
			return true
	return not any


func storefronts_armed_count() -> int:
	var n := 0
	for s in storefronts:
		if s.state_name() == &"armed":
			n += 1
	return n


func arm_storefronts() -> void:
	for s in storefronts:
		if s.visible and s.state_name() == &"cooldown":
			s.apply_build()


func spinner_spins() -> int:
	return spinner.spins_total if spinner != null else 0


func _on_rollover(index: int, was_lit: bool) -> void:
	rollover_rolled.emit(index, was_lit)


func _on_storefront_collected(id: StringName, amount: BigMoney) -> void:
	storefront_collected.emit(id, amount)


func _on_laundromat_wash(_id: StringName) -> void:
	laundromat_pass.emit()


func _on_bribe_struck(target: StandupTarget, ball_hit: Ball) -> void:
	TableScore.hit(target.id, ball_hit)
	bribe_offered.emit()


func _on_cop_struck(target: StandupTarget, ball_hit: Ball) -> void:
	if target.marked:
		return
	target.set_marked(true)
	TableScore.earn(TableScore.GROUP_BUMPERS, TableScore.BUMPER * 5.0, target.id, ball_hit)


# ============================================================== ball service =====


func spawn_ball() -> Ball:
	despawn_ball()
	_respawn_in = -1.0
	var b: Ball = BALL_SCENE.instantiate()
	b.name = "Ball"
	add_child(b)
	b.place(spawn_point())
	ball = b
	balls_served += 1
	_bind_ball()
	Balls.register(b)
	AudioDirector.play(&"ball_spawn")
	Events.ball_spawned.emit(b)
	ball_spawned.emit(b)
	return b


## An ADDITIONAL live ball, released at a plan point (or a table-space point).
func spawn_extra_ball(at: Variant = null) -> Ball:
	var b: Ball = BALL_SCENE.instantiate()
	b.name = "BallExtra%d" % balls_served
	add_child(b)
	var where := spawn_point()
	if at is Vector2 and (at as Vector2) != Vector2.ZERO:
		var p := at as Vector2
		where = Layout.p3(p, floor_height_at(p) + Feel.BALL_RADIUS + 0.02)
	elif at is Vector3:
		where = at
	b.place(where)
	balls_served += 1
	Balls.register(b)
	AudioDirector.play(&"ball_spawn")
	Events.ball_spawned.emit(b)
	ball_spawned.emit(b)
	return b


func despawn_ball() -> void:
	_respawn_in = -1.0
	if ball != null and is_instance_valid(ball):
		ball.queue_free()
	ball = null
	_bind_ball()


func _bind_ball() -> void:
	for holder: Node in [flipper_left, flipper_right, plunger, magnet, director, gate, club, docks, penthouse, city_hall]:
		if holder != null and holder.has_method(&"set_ball"):
			holder.call(&"set_ball", ball)


func _on_drain_entered(body: Node3D, sound: StringName = &"drain") -> void:
	if not (body is Ball):
		return
	_lose_ball(body as Ball, sound)


func _lose_ball(lost: Ball, sound: StringName = &"drain") -> void:
	if lost == null or not is_instance_valid(lost):
		return
	if not Balls.live().has(lost):
		return
	var was_primary := lost == ball
	if was_primary:
		ball = null
		for b in Balls.live():
			if b != lost and (ball == null or b.table_position().z > ball.table_position().z):
				ball = b
		_bind_ball()
	Balls.unregister(lost)
	lost.queue_free()
	AudioDirector.play(sound)
	Events.ball_drained.emit(lost)
	ball_lost.emit(lost)
	if auto_respawn and ball == null:
		_respawn_in = Feel.RESPAWN_DELAY


func _physics_process(delta: float) -> void:
	if _respawn_in > 0.0:
		if not auto_respawn:
			_respawn_in = -1.0
		else:
			_respawn_in -= delta
			if _respawn_in <= 0.0:
				_respawn_in = -1.0
				spawn_ball()
	_ball_search(delta)
	_keep_magnets_apart()


func _ball_search(delta: float) -> void:
	if ball == null or not is_instance_valid(ball):
		_still_for = 0.0
		return
	var p := ball.table_position()
	if ball.speed() > Feel.BALL_SEARCH_SPEED or p.z > BALL_SEARCH_FLOOR_Z or lane_box().has_point(p):
		_still_for = 0.0
		return
	for seg: Node in [club, penthouse, docks, city_hall]:
		if seg != null and bool(seg.call(&"search_exempt", ball)):
			_still_for = 0.0
			return
	if BallHold.is_held(ball):
		_still_for = 0.0
		return
	_still_for += delta
	if _still_for < Feel.BALL_SEARCH_DELAY:
		return
	_still_for = Feel.BALL_SEARCH_DELAY - Feel.BALL_SEARCH_REPEAT
	var dir := Vector3(_search_rng.randf_range(-0.55, 0.55), 0.2, -1.0).normalized()
	ball.kick(dir * Feel.BALL_SEARCH_IMPULSE)
	AudioDirector.play(&"kickback")
	ball_searched.emit(p)
