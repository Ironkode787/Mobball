extends Node2D
## Evidence-only C4 capture rig. It forces only the real table hardware required by each shot,
## parks a real ball with CameraRig in static diagnostic mode, and seeds presentation fields
## directly so screenshots show truthful target/lane states without firing gameplay callbacks.

const TABLE_SCENE := preload("res://game/table/table_main.tscn")

const LOWER_IDS: Array[StringName] = [
	&"inlane_guides", &"slingshots", &"bumper_2", &"bumper_3", &"rollovers",
	&"spinner_numbers", &"orbit_left", &"wire_bank", &"storefront_pizzeria",
	&"storefront_pawn", &"bribe_target", &"kickback_left",
]
const CLUB_IDS: Array[StringName] = [
	&"club_deck", &"staircase_ramp", &"roulette_wheel", &"slot_reels",
	&"high_roller_saucer", &"backroom_saucer", &"club_flippers",
]
const DOCKS_IDS: Array[StringName] = [
	&"docks", &"containers", &"crane", &"cargo_ramp", &"orbit_right",
]

const VIEWS := {
	&"r1": {"ids": LOWER_IDS, "at": Vector2(430.0, 1080.0), "center": Vector2(540.0, 1080.0), "zoom": 1.03},
	&"r2": {"ids": LOWER_IDS, "at": Vector2(880.0, 850.0), "center": Vector2(540.0, 950.0), "zoom": 1.03},
	&"r3": {"ids": LOWER_IDS, "at": Vector2(590.0, 1400.0), "center": Vector2(540.0, 1370.0), "zoom": 1.03},
	&"club": {"ids": LOWER_IDS + CLUB_IDS, "at": Vector2(880.0, -560.0), "center": Vector2(760.0, -420.0), "zoom": 1.42},
	&"docks": {"ids": LOWER_IDS + CLUB_IDS + DOCKS_IDS, "at": Vector2(232.0, 1300.0), "center": Vector2(288.0, 1272.0), "zoom": 1.85},
}

var table: ProgressionTable = null
var camera: CameraRig = null
var _at := Vector2.ZERO
var _view := &"r1"
var _grayscale := false
var _reported_sensory := false


func _ready() -> void:
	_view = StringName(OS.get_environment("C4_VIEW"))
	if not VIEWS.has(_view):
		_view = &"r1"
	var profile := StringName(OS.get_environment("C4_PROFILE"))
	_grayscale = profile == &"grayscale"
	if Presentation.fx != null:
		Presentation.fx.reduced_motion = profile == &"reduced_motion"
		Presentation.fx.reduced_flash = profile == &"reduced_flash"
	table = TABLE_SCENE.instantiate()
	table.name = "C4EvidenceTable"
	add_child(table)
	table.auto_respawn = false
	table.debug_all_hardware = false
	var cfg: Dictionary = VIEWS[_view]
	var requested_ids: Array[StringName] = cfg["ids"]
	if profile == &"draw_baseline":
		requested_ids = []
	elif profile == &"draw_c4":
		requested_ids = [&"rollovers", &"spinner_numbers", &"orbit_left", &"wire_bank"]
	elif profile == &"draw_c4_rollovers":
		requested_ids = [&"rollovers"]
	elif profile == &"draw_c4_spinner":
		requested_ids = [&"spinner_numbers"]
	elif profile == &"draw_c4_orbit":
		requested_ids = [&"orbit_left"]
	elif profile == &"draw_c4_wire":
		requested_ids = [&"wire_bank"]
	table.force_hardware(requested_ids)
	camera = CameraRig.new()
	camera.name = "C4EvidenceCamera"
	camera.follow_enabled = false
	# Keep the real active-table bounds so an upper-room frame cannot expose void. The
	# fixture still disables follow, making this a deterministic composition probe.
	camera.auto_bounds = true
	camera.static_center = cfg["center"]
	camera.static_zoom = cfg["zoom"]
	camera.zoom = Vector2.ONE * cfg["zoom"]
	camera.position = cfg["center"]
	add_child(camera)
	_at = cfg["at"]
	_seed_presentation_state()
	var ball := table.spawn_ball()
	ball.place(_at)
	camera.set_target(ball)
	if table.docks != null and table.docks.gate != null:
		table.docks.set_ball(ball)
	if _grayscale:
		_add_grayscale_overlay()


func _physics_process(_delta: float) -> void:
	var ball := table.ball
	if ball != null and is_instance_valid(ball):
		ball.place(_at)
	# Keep short-lived visual pulses truthful and stable for the evidence frame; these writes
	# touch only draw metadata in this fixture and never call gameplay setters.
	_seed_presentation_state()
	if not _reported_sensory and Engine.get_process_frames() >= 4:
		_reported_sensory = true
		print("C4 sensory snapshot view=", _view, " profile=", OS.get_environment("C4_PROFILE"),
				" data=", SensoryAudit.snapshot(get_tree().root, Presentation.budget))


func _seed_presentation_state() -> void:
	if OS.get_environment("C4_PROFILE") == "draw_baseline":
		return
	for rollover: Rollover in table.rollovers:
		rollover.set_lit(true)
		rollover._flash = 0.0
	if table.spinner != null:
		table.spinner._vel = 0.0
		table.spinner.spins_total = 1
	if table.wire_bank != null and not table.wire_bank.targets().is_empty():
		table.wire_bank.targets()[0].set_marked(true)
		table.wire_bank.targets()[1]._pulse = 1.0
	if table.orbit != null:
		table.orbit._entered_at = table.orbit._clock
		table.orbit._flash = 0.0
	if table.orbit_right != null:
		table.orbit_right._entered_at = table.orbit_right._clock
		table.orbit_right._flash = 0.0
	for storefront: Storefront in table.storefronts:
		if storefront._targets.is_empty():
			continue
		storefront._targets[0].down = true
		storefront._targets[0]._pulse = 0.0
		storefront._targets[0]._apply_collision()
		storefront._targets[1]._pulse = 1.0
	if _view == &"club" and table.club != null:
		if table.club.staircase != null:
			table.club.staircase._flash = 1.0
		if table.club.return_lane != null:
			table.club.return_lane._flash = 0.0
	if _view == &"docks" and table.docks != null:
		if table.docks.cargo_ramp != null:
			table.docks.cargo_ramp._flash = 1.0


func _add_grayscale_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "C4GrayscaleEvidence"
	layer.layer = 100
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform sampler2D screen_texture : hint_screen_texture, filter_linear;\nrender_mode unshaded;\nvoid fragment(){ vec4 c=texture(screen_texture,SCREEN_UV); float y=dot(c.rgb,vec3(0.299,0.587,0.114)); COLOR=vec4(vec3(y),1.0); }"
	material.shader = shader
	veil.material = material
	layer.add_child(veil)
	add_child(layer)
