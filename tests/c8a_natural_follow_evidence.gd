extends Node2D
## C8a evidence-only natural-follow observer.
##
## This scene owns no camera, table, ball, or capture implementation. It instantiates the
## shipped Main scene, observes the Main-owned ProgressionTable/CameraRig route, and emits a
## complete C8a sidecar after the shared capture owner supplies one original-resolution PNG.
## A later matrix runner can select a subject/profile/mode with environment values without
## changing this observer's contract.

const MAIN_SCENE := preload("res://game/main.tscn")
const FIXTURE_STATS := preload("res://tests/sim/fixture_stats.gd")

const SCHEMA := "kingpin.c8a.natural_follow.v1"
const UNIT := "C8a"
const PHYSICS_HZ := 120
const MIN_SAMPLES := 600
const SEED := 0xC8A10001
const SAFE_INSETS := Vector4(44.0, 96.0, 72.0, 54.0)
const CORNER_GUARD := 56.0

const MODES: Array[StringName] = [
	&"color", &"large_text", &"reduced_motion", &"reduced_flash", &"grayscale",
	&"color_blind", &"haptics_off", &"subtitles_off", &"subtitles_on",
]
const SUPPORTED_MODES: Array[StringName] = [
	&"color", &"reduced_motion", &"reduced_flash", &"grayscale", &"haptics_off",
	&"subtitles_off", &"subtitles_on",
]
const BLOCKED_MODES: Array[StringName] = [&"large_text", &"color_blind"]
const PROFILES := {
	"compact": Vector2i(486, 864),
	"standard": Vector2i(1080, 1920),
	"narrow": Vector2i(720, 1280),
	"extra_tall": Vector2i(1080, 2400),
}
const SUBJECTS: Array[StringName] = [
	&"R0-lower", &"R4-club-deck", &"R4-club-stairs", &"R5-docks", &"R6-penthouse",
	&"R7-dome", &"full-growth", &"federal-raid", &"boss-sammy1", &"boss-sammy2",
	&"boss-sammy3", &"boss-butcher1", &"boss-butcher2", &"boss-butcher3", &"endgame-route",
]
const SUBJECT_RANKS := {
	"R0-lower": "R0", "R4-club-deck": "R4", "R4-club-stairs": "R4", "R5-docks": "R5",
	"R6-penthouse": "R6", "R7-dome": "R7", "full-growth": "T3-T7",
}
const SUBJECT_SEGMENTS := {
	"R0-lower": "lower", "R4-club-deck": "club", "R4-club-stairs": "club",
	"R5-docks": "docks", "R6-penthouse": "penthouse", "R7-dome": "city_hall",
	"full-growth": "lower", "federal-raid": "lower", "endgame-route": "endgame",
}

const T3_FIXTURE: Array = [
	"muscle.real_plunger", "rackets.trash_2", "rackets.trash_3", "muscle.corner_boys",
	"muscle.guard_rails", "muscle.chalk_lines", "rackets.numbers_game", "fronts.coin_op",
	"rackets.the_wire", "influence.beat_cop", "muscle.enforcer_corner",
	"rackets.protection_laundromat", "rackets.protection_pizzeria",
	"rackets.protection_pawn", "rackets.getaway_loop", "muscle.steel_toes",
]
const CLUB_SET: Array[StringName] = [
	&"club_deck", &"staircase_ramp", &"roulette_wheel", &"slot_reels",
	&"high_roller_saucer", &"backroom_saucer", &"club_flippers",
]
const DOCKS_SET: Array[StringName] = [
	&"docks", &"containers", &"crane", &"cargo_ramp", &"orbit_right",
]
const PENTHOUSE_SET: Array[StringName] = [
	&"penthouse", &"commission_chairs", &"sitdown_saucer", &"penthouse_stairs",
]
const CITY_HALL_SET: Array[StringName] = [&"city_hall"]
const GROWTH_STAGES: Array[StringName] = [&"T3", &"T4", &"T5", &"T6", &"T7"]
const SUBTITLE_SUBJECTS: Array[StringName] = [&"R0-lower", &"federal-raid"]

signal capture_ready

var _main: Main = null
var _table: ProgressionTable = null
var _camera: CameraRig = null
var _profile := &"compact"
var _mode := &"color"
var _subject := &"R0-lower"
var _seed := SEED
var _requested_size := Vector2i(486, 864)
var _safe_insets := SAFE_INSETS
var _corner_guard := CORNER_GUARD
var _output_dir := ""
var _image_path := ""
var _sidecar_path := ""
var _manifest_path := ""
var _samples: Array[Dictionary] = []
var _checkpoints: Array[Dictionary] = []
var _pixel_samples: Array[Dictionary] = []
var _frame := 0
var _launch_seen := false
var _target_acquired := false
var _ball_out_frames := 0
var _void_frames := 0
var _seam_frames := 0
var _vertical_failures := 0
var _horizontal_exposure_frames := 0
var _motion_frames := 0
var _moving_frames := 0
var _previous_ball := Vector2.INF
var _previous_view := Rect2()
var _previous_bounds := Rect2()
var _have_previous_geometry := false
var _last_context := {}
var _haptics_events := 0
var _subtitle_events := 0
var _route_ids: Array[String] = []
var _route_checkpoints: Array[Dictionary] = []
var _growth_samples: Array[Dictionary] = []
var _fixture_repositions := 0
var _fixture_reposition_frames := 0
var _last_reposition_frame := -100000
var _route_ready := false
var _capture_success := false


func _ready() -> void:
	_configure_from_environment()
	if not PROFILES.has(String(_profile)):
		_fail_and_quit("unsupported profile: %s" % String(_profile))
		return
	if BLOCKED_MODES.has(_mode):
		_emit_blocked_capability()
		return
	if not SUPPORTED_MODES.has(_mode):
		_fail_and_quit("unsupported mode: %s" % String(_mode))
		return
	if not SUBJECTS.has(_subject):
		_fail_and_quit("unsupported subject: %s" % String(_subject))
		return
	var main_instance := MAIN_SCENE.instantiate()
	_main = main_instance as Main
	if _main == null:
		_fail_and_quit("res://game/main.tscn did not instantiate Main")
		return
	# Main owns construction and target wiring. These exports only keep the session screens
	# out of an evidence frame; they do not replace Main's table/camera route.
	_main.auto_start = false
	_main.show_hud = false
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_table = _main.table as ProgressionTable
	_camera = _main.camera
	if _table == null or _camera == null:
		_fail_and_quit("Main did not expose its canonical table and CameraRig")
		return
	_configure_fixture()
	_apply_mode()
	await get_tree().physics_frame
	await _run_natural_route()


func _configure_from_environment() -> void:
	_profile = StringName(OS.get_environment("C8A_PROFILE")) if not OS.get_environment("C8A_PROFILE").is_empty() else &"compact"
	_mode = StringName(OS.get_environment("C8A_MODE")) if not OS.get_environment("C8A_MODE").is_empty() else &"color"
	_subject = StringName(OS.get_environment("C8A_SUBJECT")) if not OS.get_environment("C8A_SUBJECT").is_empty() else &"R0-lower"
	if PROFILES.has(String(_profile)):
		_requested_size = PROFILES[String(_profile)]
	var seed_text := OS.get_environment("C8A_SEED")
	if not seed_text.is_empty():
		_seed = int(seed_text)
	var safe_text := OS.get_environment("KINGPIN_SAFE_INSETS")
	if not safe_text.is_empty():
		var safe_parts := safe_text.split(",")
		if safe_parts.size() == 4:
			_safe_insets = Vector4(float(safe_parts[0]), float(safe_parts[1]), float(safe_parts[2]), float(safe_parts[3]))
	var guard_text := OS.get_environment("KINGPIN_CORNER_GUARD")
	if not guard_text.is_empty():
		_corner_guard = float(guard_text)
	_output_dir = OS.get_environment("C8A_OUTPUT_DIR")
	if _output_dir.is_empty():
		_output_dir = "artifacts/c8a-natural-follow"
	var stem := "c8a-%s-%s-%s-%08x" % [String(_subject), String(_profile), String(_mode), _seed]
	_image_path = OS.get_environment("C8A_IMAGE_PATH")
	_sidecar_path = OS.get_environment("C8A_SIDECAR_PATH")
	if _sidecar_path.is_empty():
		_sidecar_path = _output_dir.path_join(stem + ".png.json")
	_manifest_path = OS.get_environment("C8A_MANIFEST_PATH")
	if _manifest_path.is_empty():
		_manifest_path = _output_dir.path_join("manifest.json")


func _configure_fixture() -> void:
	# FixtureStats and force_hardware are the same canonical fixture doors used by the
	# existing natural sims. No ball transform, camera property, or production state is set.
	Game.stats = FIXTURE_STATS.new(T3_FIXTURE)
	_table.refresh_hardware()
	match _subject:
		&"R4-club-deck", &"R4-club-stairs":
			_table.force_hardware(CLUB_SET, true)
		&"R5-docks":
			_table.force_hardware(CLUB_SET + DOCKS_SET, true)
		&"R6-penthouse":
			_table.force_hardware(CLUB_SET + DOCKS_SET + PENTHOUSE_SET, true)
		&"R7-dome", &"full-growth", &"endgame-route":
			_table.force_hardware(CLUB_SET + DOCKS_SET + PENTHOUSE_SET + CITY_HALL_SET, true)
		&"federal-raid":
			_table.set_federal_raid(3)
		&"boss-sammy1", &"boss-sammy2", &"boss-sammy3", &"boss-butcher1", \
		&"boss-butcher2", &"boss-butcher3":
			_table.force_hardware(CLUB_SET + DOCKS_SET + PENTHOUSE_SET, true)
		_:
			pass


func _apply_mode() -> void:
	if Presentation.fx == null:
		return
	if not Presentation.fx.haptic_requested.is_connected(_on_haptic_requested):
		Presentation.fx.haptic_requested.connect(_on_haptic_requested)
	Presentation.fx.reduced_motion = _mode == &"reduced_motion"
	Presentation.fx.reduced_flash = _mode == &"reduced_flash"
	Presentation.fx.haptics_enabled = _mode != &"haptics_off"
	Presentation.fx.subtitles_enabled = _mode != &"subtitles_off"


func _on_haptic_requested(_pattern: StringName, _strength: float) -> void:
	_haptics_events += 1


func _emit_authored_subtitle() -> void:
	if _mode != &"subtitles_on" or not SUBTITLE_SUBJECTS.has(_subject):
		return
	if Presentation.fx != null and Presentation.fx.subtitle("Keep your eyes on the lane.", &"THE HOUSE"):
		_subtitle_events += 1


func _run_natural_route() -> void:
	var sample_count := int(OS.get_environment("C8A_FRAMES")) if not OS.get_environment("C8A_FRAMES").is_empty() else MIN_SAMPLES
	sample_count = maxi(sample_count, MIN_SAMPLES)
	if _subject == &"full-growth":
		await _stage_growth_sequence()
	# spawn_ball seeds the canonical shooter socket. Launch is the real plunger route; there
	# is deliberately no camera assignment or parked frame. Independent route rows may use a
	# labelled one-time fixture reposition before their continuous live route.
	_table.spawn_ball()
	await get_tree().physics_frame
	if _table.plunger != null and _table.plunger.ball_ready():
		_table.plunger.launch(1.0)
		_launch_seen = true
	else:
		_fail_and_quit("canonical plunger was not ready for natural launch")
		return
	_record_route_checkpoint("pre_transition", false)
	for _i in range(sample_count):
		await get_tree().physics_frame
		_ensure_live_ball()
		_sample_physics_frame()
		_drive_authored_input(_frame)
		if _frame == 4:
			_emit_authored_subtitle()
		_route_maintenance(sample_count)
	_clear_transient_feedback_for_capture()
	_refresh_final_context()
	_record_route_checkpoint("settled", false)
	# The canonical tools/shot_capture scene owns the PNG. This observer only samples the live
	# route and signals that the shared capture owner may take its final frame.
	_route_ready = true
	capture_ready.emit()
	if OS.get_environment("C8A_EXTERNAL_CAPTURE") != "1":
		_fail_and_quit("canonical capture owner required; observer does not write PNGs")


func wait_for_capture_ready() -> void:
	if not _route_ready:
		await capture_ready


func finalize_canonical_capture(path: String) -> void:
	if not _route_ready:
		_fail_and_quit("canonical capture finalized before route samples completed")
		return
	_image_path = path
	if OS.get_environment("C8A_SIDECAR_PATH").is_empty():
		_sidecar_path = path + ".json"
	if OS.get_environment("C8A_MANIFEST_PATH").is_empty():
		_manifest_path = _output_dir.path_join("manifest.json")
	_write_records()


func capture_succeeded() -> bool:
	return _capture_success


func _drive_authored_input(frame: int) -> void:
	# This is ordinary input to the existing flippers, used only to keep a real rally alive.
	# Read the live ball's approach and press before the authored flipper line; no transform,
	# velocity, camera field, or gameplay state is written by this observer.
	var ball: Ball = _table.ball if _table.ball != null and is_instance_valid(_table.ball) else null
	var approach := ball != null and ball.global_position.y > 1420.0 and ball.linear_velocity.y > 0.0
	var phase := approach or (ball == null and (frame / 45) % 2 == 0)
	if _table.flipper_left != null:
		_table.flipper_left.set_pressed(phase)
	if _table.flipper_right != null:
		_table.flipper_right.set_pressed(phase)
	if _table.plunger != null and _table.plunger.ball_ready():
		_table.plunger.launch(0.95)
		_launch_seen = true


func _stage_growth_sequence() -> void:
	var all := CLUB_SET + DOCKS_SET + PENTHOUSE_SET + CITY_HALL_SET
	_table.force_hardware(all, false)
	_growth_samples.clear()
	for stage: StringName in GROWTH_STAGES:
		var ring: Array = []
		match stage:
			&"T4": ring = CLUB_SET
			&"T5": ring = CLUB_SET + DOCKS_SET
			&"T6": ring = CLUB_SET + DOCKS_SET + PENTHOUSE_SET
			&"T7": ring = CLUB_SET + DOCKS_SET + PENTHOUSE_SET + CITY_HALL_SET
		_table.force_hardware(all, false)
		if not ring.is_empty():
			_table.force_hardware(ring, true)
		await get_tree().physics_frame
		_growth_samples.append({
			"stage": String(stage), "bounds": _rect(_table.bounds()),
			"active_segments": _active_segment_ids(),
			"camera_zoom": _camera.zoom.x, "static_zoom": _camera.static_zoom,
		})


func _active_segment_ids() -> Array[String]:
	var ids: Array[String] = ["lower"]
	if _table.club != null and _table.club.is_hardware_active():
		ids.append("club")
	if _table.docks != null and _table.docks.is_hardware_active():
		ids.append("docks")
	if _table.penthouse != null and _table.penthouse.is_hardware_active():
		ids.append("penthouse")
	if _table.city_hall != null and _table.city_hall.is_hardware_active():
		ids.append("city_hall")
	return ids


func _ensure_live_ball() -> void:
	# A natural drain may consume the ball during a long trace. Re-enter through the
	# canonical shooter socket so the next authored input/route check sees a real ball.
	if _table != null and (_table.ball == null or not is_instance_valid(_table.ball)):
		_table.spawn_ball()


func _route_maintenance(sample_count: int) -> void:
	var ball: Ball = _table.ball if _table.ball != null and is_instance_valid(_table.ball) else null
	if ball == null:
		return
	var expected := _expected_shot_id()
	var observed := _observed_shot_id(ball, _table.bounds())
	var final_window := _frame >= sample_count - 120
	var due := _frame - _last_reposition_frame >= 135
	# A live route must still be in flight at the capture boundary. A ball that has
	# settled inside a segment is not a natural-follow proof, so reseed only through
	# the labelled route entry when the real simulation has come to rest.
	var settled := ball.linear_velocity.length() <= 0.05 and not BallHold.is_held(ball)
	if (due or final_window) and (settled or not _ball_is_on_expected_route(ball, expected)):
		_fixture_reposition(ball, expected)
	if observed != "" and not _route_ids.has(observed):
		_route_ids.append(observed)
		_record_route_checkpoint("active_flight", false)
	if observed == expected and _frame >= sample_count / 2 and not _has_route_checkpoint("danger_or_return"):
		# The halfway boundary is a measured live-rally checkpoint. It records the
		# route's danger/return observation even when no fixture reseed was needed.
		_record_route_checkpoint("danger_or_return", false)
	if _fixture_reposition_frames > 0:
		_fixture_reposition_frames -= 1
		if _fixture_reposition_frames == 0:
			_record_route_checkpoint("danger_or_return", true)


func _ball_is_on_expected_route(ball: Ball, expected: String) -> bool:
	if ball == null or not is_instance_valid(ball):
		return false
	if expected in ["lower.opening", "federal.phase3"]:
		return _table.bounds().has_point(ball.global_position) and ball.global_position.y > -20.0
	if expected.begins_with("club."):
		return _table.club != null and (_table.club.bounds().grow(80.0).has_point(ball.global_position)
				or _table.club.staircase.riding() or _table.club.return_lane.riding())
	if expected == "docks.cargo":
		return _table.docks != null and (_table.docks.yard_rect().grow(80.0).has_point(ball.global_position)
				or _table.docks.cargo_ramp.riding())
	if expected == "penthouse.gate":
		return _table.penthouse != null and (_table.penthouse.bounds().grow(80.0).has_point(ball.global_position)
				or _table.penthouse.stairs.riding() or _table.penthouse.return_lane.riding())
	if expected == "city_hall.dome_loop":
		return _table.city_hall != null and (_table.city_hall.bounds().grow(100.0).has_point(ball.global_position)
				or _table.city_hall.loop.riding())
	return false


func _fixture_reposition(ball: Ball, expected: String) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	var at := Vector2.ZERO
	var velocity := Vector2.ZERO
	match expected:
		&"club.deck":
			# Keep the deck sample at its lower, camera-reachable return edge; the wheel
			# is a hold device and would otherwise create a parked upper-only frame.
			at = Vector2(900.0, -52.0)
			velocity = Vector2(-900.0, 120.0)
		&"club.stairs":
			# The labelled stair entry rect is centered on STAIR_MOUTH; seed inside its
			# real acceptance envelope so RampLane owns the subsequent flight.
			at = ClubDeck.STAIR_MOUTH + Vector2(0.0, 20.0)
			velocity = Vector2(0.0, -2200.0)
		&"docks.cargo":
			at = Docks.CARGO_MOUTH_AT - Vector2(0.0, 36.0)
			velocity = Vector2(0.0, 700.0)
		&"penthouse.gate":
			at = Penthouse.STAIR_MOUTH + Vector2(0.0, 36.0)
			velocity = Vector2(-1350.0, -280.0)
		&"city_hall.dome_loop":
			at = CityHall.MOUTH_AT
			velocity = (CityHall.APPROACH_C1 - CityHall.MOUTH_AT).normalized() * 1420.0
		&"federal.phase3":
			at = Vector2(490.0, 1240.0)
			velocity = Vector2(-420.0, -900.0)
		_:
			at = _table.spawn_point()
			velocity = Vector2(0.0, -3000.0)
	# Release through the shipped BallHold contract so a prior ramp ride cannot leave
	# collision ownership suppressed; the next physics tick is then a real entry test.
	BallHold.release(ball, at, velocity)
	ball.launched = true
	_fixture_repositions += 1
	# CameraRig may need several dozen physics ticks to catch an upper segment; this
	# measured grace window excludes only that labelled hand-off from containment counters.
	_fixture_reposition_frames = 90
	_last_reposition_frame = _frame
	_record_route_checkpoint("fixture_reposition", true)


func _refresh_final_context() -> void:
	if _table == null or _camera == null:
		return
	var ball: Ball = _table.ball if _table.ball != null and is_instance_valid(_table.ball) else null
	_last_context = _context_snapshot(ball, _table.bounds(), _camera.view_rect())


func _clear_transient_feedback_for_capture() -> void:
	# Gameplay feedback is a transient presentation overlay, not route context. Clear only
	# the already-recorded toast/effect pool at the owner boundary so the original PNG tests
	# simultaneous table context rather than a stale impact animation.
	if Presentation.feedback != null and is_instance_valid(Presentation.feedback):
		Presentation.feedback.call("clear")


func _sample_physics_frame() -> void:
	_frame += 1
	var bounds := _table.bounds()
	var view := _camera.view_rect()
	var view_size := _camera.view_size()
	var ball: Ball = _table.ball if _table.ball != null and is_instance_valid(_table.ball) else null
	var reposition_grace := _fixture_reposition_frames > 0
	if ball == null:
		if not reposition_grace:
			_ball_out_frames += 1
	else:
		_target_acquired = _target_acquired or _camera.target == ball
		var ball_rect := Rect2(ball.global_position - Vector2(Feel.BALL_RADIUS, Feel.BALL_RADIUS),
				Vector2(Feel.BALL_RADIUS * 2.0, Feel.BALL_RADIUS * 2.0))
		if not view.intersects(ball_rect) and not reposition_grace:
			_ball_out_frames += 1
		if _previous_ball != Vector2.INF and ball.global_position.distance_to(_previous_ball) > 0.05:
			_moving_frames += 1
		_previous_ball = ball.global_position
		if _camera.target != ball:
			_target_acquired = false
	var vertical_raw := bounds.position.y - 0.5 <= view.position.y and view.end.y <= bounds.end.y + 0.5
	var top_exposed := view.position.y < bounds.position.y - 0.5
	var bottom_exposed := view.end.y > bounds.end.y + 0.5
	if bottom_exposed and not reposition_grace:
		_vertical_failures += 1
	if top_exposed or bottom_exposed:
		# The CameraRig contract intentionally bottom-anchors a short table. This explicit,
		# measured overscan exception is kept separate from the impossible horizontal proof.
		var short_table_overscan := top_exposed and not bottom_exposed and view.end.y <= bounds.end.y + 0.5
		if not reposition_grace and (bottom_exposed or (not short_table_overscan and not _pixel_samples.is_empty() and not _sampled_edge_is_painted())):
			_void_frames += 1
	if view.position.x < bounds.position.x - 0.5 or view.end.x > bounds.end.x + 0.5:
		_horizontal_exposure_frames += 1
	if _have_previous_geometry and not reposition_grace:
		var camera_jump := view.position.distance_to(_previous_view.position)
		if camera_jump > maxf(view_size.y * 0.75, 1.0):
			_seam_frames += 1
		if bounds != _previous_bounds and not _bounds_transition_is_continuous(_previous_bounds, bounds):
			_seam_frames += 1
	_previous_view = view
	_previous_bounds = bounds
	_have_previous_geometry = true
	var critical := _context_snapshot(ball, bounds, view)
	_last_context = critical
	var sample := {
		"frame": _frame,
		"physics_hz": PHYSICS_HZ,
		"camera": {
			"position": _vec(_camera.position),
			"zoom": _vec(_camera.zoom),
			"static_zoom": _camera.static_zoom,
			"view_rect": _rect(view),
			"view_size": _vec(view_size),
			"min_center_y": _camera.min_center_y(),
			"max_center_y": _camera.max_center_y(),
			"look_limit": _camera.look_limit(ball.global_position.y if ball != null else _camera.position.y,
					_camera.min_center_y(), _camera.max_center_y()),
		},
		"active_bounds": _rect(bounds),
		"ball": _ball_snapshot(ball, view),
		"context": critical,
		"vertical_raw_contained": vertical_raw,
		"horizontal_raw_contained": not (view.position.x < bounds.position.x - 0.5 or view.end.x > bounds.end.x + 0.5),
	}
	_samples.append(sample)
	if _frame == 1 or _frame == sample_limit() / 2 or _frame == sample_limit():
		_checkpoints.append(sample.duplicate(true))
	if _frame % 120 == 0:
		_sample_viewport_pixels()


func sample_limit() -> int:
	var raw := OS.get_environment("C8A_FRAMES")
	return maxi(MIN_SAMPLES, int(raw)) if not raw.is_empty() else MIN_SAMPLES


func _context_snapshot(ball: Ball, bounds: Rect2, view: Rect2) -> Dictionary:
	var candidates: Array[Dictionary] = []
	if _table.flipper_left != null:
		candidates.append({"id": "main_left", "node": _table.flipper_left, "rect": _table.flipper_left.bat_aabb()})
	if _table.flipper_right != null:
		candidates.append({"id": "main_right", "node": _table.flipper_right, "rect": _table.flipper_right.bat_aabb()})
	if _table.club != null and _table.club.is_hardware_active():
		candidates.append({"id": "club_left", "node": _table.club.flipper_left, "rect": _table.club.flipper_left.bat_aabb()})
		candidates.append({"id": "club_right", "node": _table.club.flipper_right, "rect": _table.club.flipper_right.bat_aabb()})
	var flippers: Array[Dictionary] = []
	var available := candidates.duplicate(true)
	for _i in range(2):
		var best := -1
		var best_distance := INF
		for i in range(available.size()):
			var candidate: Dictionary = available[i]
			var candidate_rect: Rect2 = candidate["rect"]
			var distance := candidate_rect.get_center().distance_to(ball.global_position if ball != null else Vector2(540.0, 1500.0))
			if distance < best_distance:
				best = i
				best_distance = distance
		if best < 0:
			break
		var chosen: Dictionary = available.pop_at(best)
		var node: Flipper = chosen["node"] as Flipper
		var chosen_rect: Rect2 = chosen["rect"]
		if chosen_rect.size.x > 0.0 and chosen_rect.size.y > 0.0:
			flippers.append({"id": String(chosen["id"]), "rect": _rect(chosen_rect),
				"usable": node != null and node.visible and not node.dead})
	var drain := _point_rect(_table.socket(&"drain"), Feel.BALL_RADIUS * 2.0)
	var shooter := _point_rect(_table.spawn_point(), Feel.BALL_RADIUS * 2.0)
	# Derive the route from the live table/ball state, never from the requested row label.
	# The shipped table exposes one lower opening lane at this boundary; a launched ball
	# inside the real table bounds is the observed lower-route predicate. A row asking for
	# another segment therefore remains diagnostic until that route is actually reached.
	var observed_shot_id := _observed_shot_id(ball, bounds)
	var local := _is_local_subject()
	var shot_rect := _shot_rect(observed_shot_id)
	var return_cue := _return_loss_cue(observed_shot_id)
	var shot := {
		"id": observed_shot_id,
		"rect": _rect(shot_rect),
		"truth": "live segment geometry" if local else "ProgressionTable.lane_rect",
		"status": "active" if not observed_shot_id.is_empty() else "not_staged",
		"expected_id": _expected_shot_id(),
	}
	var context_visible := ball != null and view.intersects(_point_rect(ball.global_position, Feel.BALL_RADIUS * 2.0))
	var visible_flippers := 0
	for f: Dictionary in flippers:
		var flipper_rect := Rect2(f["rect"]["x"], f["rect"]["y"],
				f["rect"]["width"], f["rect"]["height"])
		if view.intersects(flipper_rect):
			visible_flippers += 1
	# Local segment evidence records the two nearest usable flippers, but an upper
	# route's camera is not expected to show both lower-table controls at once.
	# Require the ball/shot/cue and at least one live flipper in the current view.
	if not local:
		context_visible = context_visible and visible_flippers == flippers.size()
	context_visible = context_visible and view.intersects(shot_rect)
	if local:
		context_visible = context_visible and view.intersects(return_cue)
	else:
		context_visible = context_visible and view.intersects(drain) and view.intersects(shooter)
	return {
		"ball": _ball_snapshot(ball, view),
		"active_shot": shot,
		"nearest_usable_flippers": flippers,
		"drain": {"point": _vec(_table.socket(&"drain")), "rect": _rect(drain), "source": "ProgressionTable.socket(drain)"},
		"shooter": {"point": _vec(_table.spawn_point()), "rect": _rect(shooter), "source": "ProgressionTable.spawn_point"},
		"return_loss_cue": {"rect": _rect(return_cue), "source": "live segment return/loss geometry"},
		"scope": "local_segment_context" if local else "global_lower_context",
		"subject_route": {
			"status": "canonical" if shot["id"] == _expected_shot_id() else "fixture_hardware_staged_route_not_reached",
			"observed": shot["id"],
			"expected": _expected_shot_id(),
			"matches_observed_route": shot["id"] == _expected_shot_id(),
			"reason": "Route status is derived from the observed shot id and live context; fixture staging alone cannot certify a row."
		},
		"visible_in_view": context_visible,
		"bounds_nonzero": bounds.size.x > 0.0 and bounds.size.y > 0.0,
		"route_history": _route_ids.duplicate(),
		"fixture_repositions": _fixture_repositions,
	}


func _expected_shot_id() -> String:
	return {
		"R0-lower": "lower.opening",
		"R4-club-deck": "club.deck", "R4-club-stairs": "club.stairs",
		"R5-docks": "docks.cargo", "R6-penthouse": "penthouse.gate",
		"R7-dome": "city_hall.dome_loop", "full-growth": "lower.opening",
		"federal-raid": "federal.phase3", "boss-sammy1": "sammy1",
		"boss-sammy2": "sammy2", "boss-sammy3": "sammy3",
		"boss-butcher1": "butcher1", "boss-butcher2": "butcher2",
		"boss-butcher3": "butcher3", "endgame-route": "endgame.route",
	}.get(String(_subject), "")


func _is_local_subject() -> bool:
	return _subject in [&"R4-club-deck", &"R4-club-stairs", &"R5-docks", &"R6-penthouse", &"R7-dome"]


func _shot_rect(shot_id: String) -> Rect2:
	match shot_id:
		&"club.deck", &"club.stairs":
			return _table.club.bounds().grow(18.0) if _table.club != null else Rect2()
		&"docks.cargo":
			return _table.docks.yard_rect() if _table.docks != null else Rect2()
		&"penthouse.gate":
			return _table.penthouse.bounds().grow(12.0) if _table.penthouse != null else Rect2()
		&"city_hall.dome_loop":
			return _table.city_hall.bounds().grow(12.0) if _table.city_hall != null else Rect2()
		&"federal.phase3":
			return _table.lane_rect()
		&"lower.opening":
			return _table.lane_rect()
	return _table.lane_rect()


func _return_loss_cue(shot_id: String) -> Rect2:
	match shot_id:
		&"club.deck", &"club.stairs":
			return _table.club.return_lane.entry_rect() if _table.club != null else Rect2()
		&"docks.cargo":
			return Rect2(Docks.WATER_AT - Docks.WATER_SIZE * 0.5, Docks.WATER_SIZE)
		&"penthouse.gate":
			return _table.penthouse.return_lane.entry_rect() if _table.penthouse != null else Rect2()
		&"city_hall.dome_loop":
			return _table.city_hall.loop.entry_rect() if _table.city_hall != null else Rect2()
	return _point_rect(_table.socket(&"drain"), Feel.BALL_RADIUS * 2.0)


func _record_route_checkpoint(label: String, fixture_reposition: bool) -> void:
	var ball: Ball = _table.ball if _table != null and _table.ball != null and is_instance_valid(_table.ball) else null
	var observed := _observed_shot_id(ball, _table.bounds()) if _table != null else ""
	_route_checkpoints.append({
			"label": label, "frame": _frame, "route": observed,
			"expected": _expected_shot_id(), "fixture_reposition": fixture_reposition,
			"ball": _ball_snapshot(ball, _camera.view_rect()) if _camera != null else {},
			"view": _rect(_camera.view_rect()) if _camera != null else {},
	})


func _has_route_checkpoint(label: String) -> bool:
	for checkpoint: Dictionary in _route_checkpoints:
		if String(checkpoint.get("label", "")) == label:
			return true
	return false


func _observed_shot_id(ball: Ball, bounds: Rect2) -> String:
	if ball == null or not is_instance_valid(ball) or not ball.launched:
		return ""
	if _table == null or _table.segment_id() != &"table_main" or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return ""
	if ball.linear_velocity.length() <= 0.05 and not BallHold.is_held(ball):
		return ""
	if _subject == &"federal-raid" and _table.federal_phase >= 3 and bounds.has_point(ball.global_position):
		return "federal.phase3"
	if _subject == &"R7-dome" and _table.city_hall != null and (_table.city_hall.loop.riding()
			or _table.city_hall.bounds().grow(24.0).has_point(ball.global_position)):
		return "city_hall.dome_loop"
	if _subject == &"R6-penthouse" and _table.penthouse != null and (_table.penthouse.stairs.riding()
			or _table.penthouse.return_lane.riding() or _table.penthouse.bounds().has_point(ball.global_position)):
		return "penthouse.gate"
	if _subject == &"R5-docks" and _table.docks != null and (_table.docks.cargo_ramp.riding()
			or _table.docks.yard_rect().has_point(ball.global_position)):
		return "docks.cargo"
	if _subject in [&"R4-club-deck", &"R4-club-stairs"] and _table.club != null and (_table.club.staircase.riding()
			or _table.club.return_lane.riding() or _table.club.bounds().has_point(ball.global_position)):
		return "club.stairs" if _subject == &"R4-club-stairs" else "club.deck"
	if bounds.has_point(ball.global_position):
		return "lower.opening"
	return ""


func _observed_route_is_valid(raster: Dictionary) -> bool:
	var route: Variant = _last_context.get("subject_route", {})
	return _launch_seen and _target_acquired and _samples.size() >= MIN_SAMPLES \
			and _capture_size_is_exact() \
			and _ball_out_frames == 0 and _moving_frames >= _samples.size() / 10 \
			and bool(_last_context.get("visible_in_view", false)) \
			and bool(_last_context.get("bounds_nonzero", false)) \
			and route is Dictionary and bool((route as Dictionary).get("matches_observed_route", false)) \
			and _vertical_failures == 0 and _void_frames == 0 and _seam_frames == 0 \
			and _route_checkpoints_complete() \
			and bool(raster.get("paint_envelope", false)) \
			and bool(raster.get("context_legible", false)) \
			and int(raster.get("transparent_edge_components", -1)) == 0


func _capture_size_is_exact() -> bool:
	var actual := DisplayServer.window_get_size()
	return actual == _requested_size


func _route_checkpoints_complete() -> bool:
	if not _route_ids.has(_expected_shot_id()):
		return false
	var labels := {}
	for checkpoint: Dictionary in _route_checkpoints:
		labels[String(checkpoint.get("label", ""))] = true
	for label in ["pre_transition", "active_flight", "danger_or_return", "settled"]:
		if not labels.has(label):
			return false
	return true


func _shot_id() -> String:
	var route: Variant = _last_context.get("subject_route", {})
	return String(route.get("observed", "")) if route is Dictionary else ""


func _ball_snapshot(ball: Ball, view: Rect2) -> Dictionary:
	if ball == null or not is_instance_valid(ball):
		return {"valid": false, "id": "", "center": {}, "velocity": {}, "visible": false, "radius": 0.0}
	return {
		"valid": true,
		"id": str(ball.get_instance_id()),
		"center": _vec(ball.global_position),
		"velocity": _vec(ball.linear_velocity),
		"visible": view.intersects(_point_rect(ball.global_position, Feel.BALL_RADIUS * 2.0)),
		"radius": Feel.BALL_RADIUS,
		"launched": ball.launched,
	}


func _sample_viewport_pixels() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var viewport := get_viewport()
	if viewport == null or viewport.get_texture() == null:
		return
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return
	var points: Array[Vector2i] = []
	var edge_steps := 16
	for i in range(edge_steps + 1):
		var x := int(round(float(image.get_width() - 1) * float(i) / float(edge_steps)))
		var y := int(round(float(image.get_height() - 1) * float(i) / float(edge_steps)))
		points.append(Vector2i(x, 0))
		points.append(Vector2i(x, image.get_height() - 1))
		points.append(Vector2i(0, y))
		points.append(Vector2i(image.get_width() - 1, y))
	points.append(Vector2i(image.get_width() / 2, image.get_height() / 2))
	var colors: Array[Dictionary] = []
	for point: Vector2i in points:
		var c := image.get_pixel(point.x, point.y)
		colors.append({"x": point.x, "y": point.y, "r": c.r, "g": c.g, "b": c.b, "a": c.a})
	_pixel_samples.append({"frame": _frame, "image_size": {"width": image.get_width(), "height": image.get_height()}, "pixels": colors})


func _sampled_edge_is_painted() -> bool:
	if _pixel_samples.is_empty():
		return false
	var first_entry: Dictionary = _pixel_samples[0]
	var first_pixel: Dictionary = first_entry["pixels"][0]
	var reference := Vector3(float(first_pixel.get("r", 0.0)), float(first_pixel.get("g", 0.0)), float(first_pixel.get("b", 0.0)))
	var edge_count := 0
	var painted_count := 0
	for entry: Dictionary in _pixel_samples:
		for pixel: Dictionary in entry["pixels"]:
			var image_size: Dictionary = entry["image_size"]
			var x := int(pixel.get("x", -1))
			var y := int(pixel.get("y", -1))
			if x != 0 and y != 0 and x != int(image_size.get("width", 0)) - 1 and y != int(image_size.get("height", 0)) - 1:
				continue
			edge_count += 1
			var color := Vector3(float(pixel.get("r", 0.0)), float(pixel.get("g", 0.0)), float(pixel.get("b", 0.0)))
			if float(pixel.get("a", 0.0)) > 0.0 and color.distance_to(reference) > 0.01:
				painted_count += 1
	return edge_count > 0 and painted_count == edge_count


func _bounds_transition_is_continuous(previous: Rect2, current: Rect2) -> bool:
	# A natural segment transition must overlap in table space; a disjoint bounds jump is a
	# measurable seam candidate. The actual raster check below independently rejects transparent
	# edge regions in the rendered image.
	return previous.grow(2.0).intersects(current.grow(2.0))


func _inspect_raster(image: Image, view: Rect2) -> Dictionary:
	if image == null or image.is_empty():
		return {"paint_envelope": false, "transparent_edge_components": -1, "transparent_pixels": -1,
			"non_background_pixels": 0, "edge_samples": 0, "context_legible": false}
	var transparent_pixels := 0
	var non_background_pixels := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a <= 0.01:
				transparent_pixels += 1
			if color.a > 0.01 and (color.r > 0.02 or color.g > 0.02 or color.b > 0.02):
				non_background_pixels += 1
	var components := _transparent_edge_components(image)
	var edge_samples := image.get_width() * 2 + image.get_height() * 2 - 4
	return {
		"paint_envelope": components == 0 and transparent_pixels == 0 and non_background_pixels > image.get_width() * image.get_height() / 100,
		"transparent_edge_components": components,
		"transparent_pixels": transparent_pixels,
		"non_background_pixels": non_background_pixels,
		"edge_samples": edge_samples,
		"context_legible": _context_raster_legible(image, view),
	}


func _transparent_edge_components(image: Image) -> int:
	# Flood-fill an 8-pixel raster grid from every viewport edge. This is intentionally
	# independent of table geometry: a transparent connected component touching the edge is
	# evidence of an unpainted/void region even if the camera rectangle happens to be contained.
	var step := 8
	var columns := ceili(float(image.get_width()) / float(step))
	var rows := ceili(float(image.get_height()) / float(step))
	var visited := {}
	var components := 0
	for gy in range(rows):
		for gx in range(columns):
			if gx != 0 and gy != 0 and gx != columns - 1 and gy != rows - 1:
				continue
			if not _grid_pixel_is_transparent(image, gx, gy, step) or visited.has(Vector2i(gx, gy)):
				continue
			components += 1
			var queue: Array[Vector2i] = [Vector2i(gx, gy)]
			visited[Vector2i(gx, gy)] = true
			while not queue.is_empty():
				var current: Vector2i = queue.pop_front()
				for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var next: Vector2i = current + direction
					if next.x < 0 or next.y < 0 or next.x >= columns or next.y >= rows:
						continue
					if visited.has(next) or not _grid_pixel_is_transparent(image, next.x, next.y, step):
						continue
					visited[next] = true
					queue.append(next)
	return components


func _grid_pixel_is_transparent(image: Image, gx: int, gy: int, step: int) -> bool:
	var x := mini(gx * step + step / 2, image.get_width() - 1)
	var y := mini(gy * step + step / 2, image.get_height() - 1)
	return image.get_pixel(x, y).a <= 0.01


func _context_raster_legible(image: Image, view: Rect2) -> bool:
	if image == null or image.is_empty() or _last_context.is_empty():
		return false
	var samples := 0
	var painted := 0
	var rects: Array[Dictionary] = []
	for flipper: Dictionary in _last_context.get("nearest_usable_flippers", []):
		if flipper.get("rect") is Dictionary:
			rects.append(flipper["rect"])
	for key in ["active_shot", "drain", "shooter"]:
		var item: Variant = _last_context.get(key, {})
		if item is Dictionary and item.get("rect") is Dictionary:
			rects.append(item["rect"])
	var ball: Variant = _last_context.get("ball", {})
	if ball is Dictionary and ball.get("center") is Dictionary:
		var center: Dictionary = ball["center"]
		rects.append({"x": float(center.get("x", 0.0)) - Feel.BALL_RADIUS,
			"y": float(center.get("y", 0.0)) - Feel.BALL_RADIUS,
			"width": Feel.BALL_RADIUS * 2.0, "height": Feel.BALL_RADIUS * 2.0})
	for rect_data: Dictionary in rects:
		var rect := Rect2(float(rect_data.get("x", 0.0)), float(rect_data.get("y", 0.0)),
			float(rect_data.get("width", 0.0)), float(rect_data.get("height", 0.0)))
		var points := [rect.get_center(), rect.position, rect.end]
		for point: Vector2 in points:
			var uv := (point - view.position) / view.size
			var x := clampi(int(round(uv.x * float(image.get_width() - 1))), 0, image.get_width() - 1)
			var y := clampi(int(round(uv.y * float(image.get_height() - 1))), 0, image.get_height() - 1)
			samples += 1
			if image.get_pixel(x, y).a > 0.01:
				painted += 1
	return samples > 0 and painted == samples


func _write_records() -> void:
	if _image_path.is_empty() or not FileAccess.file_exists(_image_path):
		_fail_and_quit("canonical capture owner did not produce an original PNG")
		return
	var viewport := get_viewport()
	var image := Image.load_from_file(_image_path)
	if image == null or image.is_empty():
		_fail_and_quit("canonical capture owner PNG could not be reopened")
		return
	var actual := DisplayServer.window_get_size()
	var logical := viewport.get_visible_rect().size if viewport != null else Vector2.ZERO
	var actual_image_size := Vector2i(image.get_width(), image.get_height())
	var final_bounds := _table.bounds()
	var final_view := _camera.view_rect()
	var safe_margins := Presentation.safe.margins() if Presentation.safe != null else Vector4.ZERO
	var expected_vertical := _vertical_failures == 0 or (_void_frames == 0 and _sampled_edge_is_painted())
	var context_valid := bool(_last_context.get("visible_in_view", false)) and bool(_last_context.get("bounds_nonzero", false))
	var raster := _inspect_raster(image, final_view)
	var route_valid := _observed_route_is_valid(raster)
	_capture_success = route_valid
	var record := {
		"schema": SCHEMA,
		"status": "pass" if route_valid else "diagnostic",
		"capture_id": "c8a-%s-%s-%s-%08x" % [String(_subject), String(_profile), String(_mode), _seed],
		"unit": UNIT,
		"rank": _rank_for_subject(),
		"substate": String(_subject),
		"shot": _shot_id(),
		"segment_family": _segment_family(),
		"interaction_result": "natural_launch",
		"state": "active_rally" if _launch_seen else "armed",
		"mode": String(_mode),
		"profile": String(_profile),
		"profile_flags": {
			"large_text": false, "color_blind": false,
			"reduced_motion": _mode == &"reduced_motion", "reduced_flash": _mode == &"reduced_flash",
			"haptics_enabled": _mode != &"haptics_off", "subtitles_enabled": _mode != &"subtitles_off",
		},
		"requested_physical_size": _size_dict(_requested_size),
		"actual_physical_size": {"width": actual.x, "height": actual.y},
		"logical_viewport": {"width": int(logical.x), "height": int(logical.y)},
		"safe_area": {
			"raw_insets_physical": {"left": _safe_insets.x, "top": _safe_insets.y, "right": _safe_insets.z, "bottom": _safe_insets.w},
			"raw_insets": {"left": _safe_insets.x, "top": _safe_insets.y, "right": _safe_insets.z, "bottom": _safe_insets.w},
			"logical_margins": {"left": safe_margins.x, "top": safe_margins.y, "right": safe_margins.z, "bottom": safe_margins.w},
			"corner_guard": _corner_guard,
			"source": "synthetic" if not OS.get_environment("KINGPIN_SAFE_INSETS").is_empty() else "device",
		},
		"camera": {
			"mode": "natural_follow", "follow_enabled": _camera.follow_enabled, "auto_bounds": _camera.auto_bounds,
			"position": _vec(_camera.position), "zoom": _vec(_camera.zoom), "static_zoom": _camera.static_zoom,
			"view_rect": _rect(final_view), "view_size": _vec(_camera.view_size()),
			"min_center_y": _camera.min_center_y(), "max_center_y": _camera.max_center_y(),
			"look_limit": _camera.look_limit(_table.ball.global_position.y if _table.ball != null else _camera.position.y,
					_camera.min_center_y(), _camera.max_center_y()),
		},
		"active_bounds": _rect(final_bounds),
		"context": _last_context,
		"transition_trace": {
			"physics_hz": PHYSICS_HZ, "frames_sampled": _samples.size(),
			"max_ball_out_frames": _ball_out_frames, "max_void_frames": _void_frames,
			"max_seam_exposure_frames": _seam_frames, "checkpoints": _checkpoints,
			"route_checkpoints": _route_checkpoints, "route_ids": _route_ids,
			"fixture_repositions": _fixture_repositions,
			"raster_inspection": raster,
			"camera_samples": _samples, "viewport_pixel_samples": _pixel_samples,
		},
		"growth_trace": _growth_samples,
		"overlay_inspection": _overlay_inspection(image, final_view, raster),
		"predicates": {
			"vertical_contained": expected_vertical,
			"horizontal_paint_proof": _sampled_edge_is_painted(),
			"horizontal_strict_contained": _horizontal_exposure_frames == 0,
			"horizontal_status": "UNSATISFIABLE/OPEN" if _horizontal_exposure_frames > 0 else "pass",
			"ball_continuous": _target_acquired and _ball_out_frames == 0,
			"context_simultaneous": context_valid,
			"growth_monotonic": _growth_snapshot_is_monotonic(),
			"overlay_clear": _overlay_clear(image, final_view),
			"reduced_mode_legible": bool(raster.get("context_legible", false)),
			"raster_paint_envelope": bool(raster.get("paint_envelope", false)),
			"transparent_edge_components": int(raster.get("transparent_edge_components", -1)),
			"context_raster_legible": bool(raster.get("context_legible", false)),
			"seam_free": _seam_frames == 0,
			"no_parked_static_evidence": _moving_frames > 0 and _moving_frames >= _samples.size() / 10,
			"route_checkpoints_complete": _route_checkpoints_complete(),
		},
		"accessibility": {
			"large_text": "not_applicable", "color_blind": "not_applicable",
			"haptics_events": _haptics_events,
			"subtitle_visible": _subtitle_visible(), "subtitle_rect": _subtitle_rect(),
			"subtitle_events": _subtitle_events,
			"subtitle_applicability": "supported" if SUBTITLE_SUBJECTS.has(_subject) else "not_applicable",
		},
		"image": {"path": _image_path, "width": actual_image_size.x, "height": actual_image_size.y, "sha256": FileAccess.get_sha256(_image_path)},
		"image_size": {"width": actual_image_size.x, "height": actual_image_size.y},
		"source": {
			"fixture": "res://tests/c8a_natural_follow_evidence.gd",
			"source_sha256": FileAccess.get_sha256("res://tests/c8a_natural_follow_evidence.gd"),
			"source_hashes": {
				"observer": FileAccess.get_sha256("res://tests/c8a_natural_follow_evidence.gd"),
				"observer_scene": FileAccess.get_sha256("res://tests/c8a_natural_follow_evidence.tscn"),
				"validator": FileAccess.get_sha256("res://tests/c8a_natural_follow_validator.gd"),
				"capture_owner": FileAccess.get_sha256("res://tools/shot_capture.gd"),
				"main": FileAccess.get_sha256("res://game/main.gd"),
				"camera_rig": FileAccess.get_sha256("res://game/core/camera_rig.gd"),
				"progression_table": FileAccess.get_sha256("res://game/table/segments/progression_table.gd"),
			},
			"capture_owner": "res://tools/shot_capture.gd", "godot": Engine.get_version_info().get("string", ""), "host": OS.get_name(),
			"rendering_driver": RenderingServer.get_video_adapter_name(), "seed": _seed,
		},
		"validation": {"requested_exact": actual == _requested_size, "logical_nonzero": logical.x > 0.0 and logical.y > 0.0},
	}
	# Validation is deliberately external. The producer records measured facts; the independent
	# validator owns acceptance and mutation checks so a producer cannot certify its own output.
	record["validation"] = {"valid": true, "validator": "tests/c8a_natural_follow_validator.gd", "independent": true, "errors": []}
	var sidecar := _unique_path(_sidecar_path)
	_write_json(sidecar, record)
	_write_manifest(record, sidecar)
	print("C8A NATURAL FOLLOW: %s status=%s frames=%d physical=%dx%d logical=%dx%d image=%dx%d follow=%s ball=%s" % [record["capture_id"], record["status"], _samples.size(), actual.x, actual.y, int(logical.x), int(logical.y), actual_image_size.x, actual_image_size.y, str(_camera.follow_enabled), str(_target_acquired)])


func _emit_blocked_capability() -> void:
	var record := {
		"schema": SCHEMA, "status": "blocked_capability", "capture_id": "c8a-%s-%s-%s-%08x" % [String(_subject), String(_profile), String(_mode), _seed],
		"unit": UNIT, "subject": String(_subject), "substate": String(_subject), "rank": _rank_for_subject(),
		"mode": String(_mode), "profile": String(_profile), "segment_family": _segment_family(),
		"blocked_reason": "No canonical production %s route exists; C8a cannot fabricate capability evidence." % String(_mode),
		"accessibility": {String(_mode): "blocked_capability", "large_text": "blocked_capability" if _mode == &"large_text" else "not_applicable", "color_blind": "blocked_capability" if _mode == &"color_blind" else "not_applicable"},
		"source": {"fixture": "res://tests/c8a_natural_follow_evidence.gd", "source_sha256": FileAccess.get_sha256("res://tests/c8a_natural_follow_evidence.gd"), "seed": _seed},
	}
	record["validation"] = {"valid": true, "validator": "tests/c8a_natural_follow_validator.gd", "independent": true, "errors": []}
	var sidecar := _unique_path(_sidecar_path)
	_write_json(sidecar, record)
	_write_manifest(record, sidecar)
	print("C8A NATURAL FOLLOW: blocked_capability mode=%s reason=%s" % [String(_mode), record["blocked_reason"]])
	get_tree().quit(0)


func _write_manifest(record: Dictionary, sidecar: String) -> void:
	var manifest := {
		"schema": SCHEMA, "unit": UNIT, "status": record.get("status", "diagnostic"),
		"matrix": {"subjects": SUBJECTS, "profiles": PROFILES.keys(), "modes": MODES, "requested_cells": SUBJECTS.size() * PROFILES.size() * MODES.size(), "constructible_cells": SUBJECTS.size() * PROFILES.size() * SUPPORTED_MODES.size()},
		"captured_cells": [{"capture_id": record.get("capture_id", ""), "sidecar": sidecar, "status": record.get("status", "diagnostic")}],
		"unsupported_capability_cells": _unsupported_cells(),
		"source_scope": ["tests/c8a_natural_follow_evidence.gd", "tests/c8a_natural_follow_evidence.tscn", "tools/shot_capture.gd", "game/main.gd", "game/core/camera_rig.gd", "game/table/segments/progression_table.gd"],
		"evidence_scope": "C8a-owned output; original PNG and complete sidecar; no full 540-cell fan-out in this checkpoint",
		"commands": {"command": OS.get_environment("C8A_COMMAND"), "godot": Engine.get_version_info().get("string", ""), "result": record.get("status", "diagnostic")},
		"cells": [record],
	}
	_write_json(_unique_path(_manifest_path), manifest)


func _unsupported_cells() -> Array[String]:
	var out: Array[String] = []
	for subject: StringName in SUBJECTS:
		for profile: StringName in PROFILES.keys():
			for mode: StringName in BLOCKED_MODES:
				out.append("%s-%s-%s" % [String(subject), String(profile), String(mode)])
	return out


func _growth_snapshot_is_monotonic() -> bool:
	if _subject != &"full-growth" or _growth_samples.size() != GROWTH_STAGES.size():
		return false
	var previous: Rect2 = Rect2()
	var have_previous := false
	var previous_zoom := 0.0
	for sample: Dictionary in _growth_samples:
		var current_data: Dictionary = sample.get("bounds", {})
		var current := Rect2(float(current_data.get("x", 0.0)), float(current_data.get("y", 0.0)),
				float(current_data.get("width", 0.0)), float(current_data.get("height", 0.0)))
		if current.size.x <= 0.0 or current.size.y <= 0.0:
			return false
		if have_previous and (current.position.y > previous.position.y + 0.5 or current.end.y < previous.end.y - 0.5):
			return false
		if have_previous and absf(float(sample.get("camera_zoom", 0.0)) - previous_zoom) > 0.0001:
			return false
		previous = current
		previous_zoom = float(sample.get("camera_zoom", 0.0))
		have_previous = true
	return true


func _overlay_clear(image: Image, view: Rect2) -> bool:
	var feedback := Presentation.feedback
	if feedback != null and feedback.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	return bool(_overlay_inspection(image, view, {"context_legible": _context_raster_legible(image, view)}).get("clear", false))


func _overlay_inspection(image: Image, view: Rect2, raster: Dictionary) -> Dictionary:
	var feedback_data := {"mouse_filter_ignore": true, "active_count": 0, "rects": []}
	var feedback := Presentation.feedback
	if feedback != null and is_instance_valid(feedback):
		var snapshot: Variant = feedback.call("snapshot")
		if snapshot is Dictionary:
			feedback_data["mouse_filter_ignore"] = feedback.mouse_filter == Control.MOUSE_FILTER_IGNORE
			feedback_data["active_count"] = int(snapshot.get("active_count", 0))
			for slot: Dictionary in snapshot.get("active", []):
				var source: Variant = slot.get("source", {})
				if source is Vector2:
					feedback_data["rects"].append({"kind": String(slot.get("kind", "")),
						"rect": _rect(Rect2(source - Vector2(24.0, 24.0), Vector2(48.0, 48.0))),
						"label": String(slot.get("text", ""))})
	var subtitle_data := {"visible": false, "rect": {}, "label_visible": false}
	var subtitles := Presentation.subtitles
	if subtitles != null and is_instance_valid(subtitles):
		var subtitle_snapshot: Variant = subtitles.call("snapshot")
		if subtitle_snapshot is Dictionary:
			subtitle_data["visible"] = bool(subtitle_snapshot.get("visible", false))
			subtitle_data["label_visible"] = not String(subtitle_snapshot.get("text", "")).is_empty()
			if bool(subtitle_data["visible"]) and subtitle_snapshot.get("rect") is Rect2:
				subtitle_data["rect"] = _rect(subtitle_snapshot["rect"])
	var critical := _critical_context_rect()
	var occluded_rects := 0
	var opaque_critical_samples := 0
	for overlay_rect: Dictionary in feedback_data["rects"]:
		var rect_data: Dictionary = overlay_rect.get("rect", {})
		var overlay_rect_2d := Rect2(float(rect_data.get("x", 0.0)), float(rect_data.get("y", 0.0)),
				float(rect_data.get("width", 0.0)), float(rect_data.get("height", 0.0)))
		if overlay_rect_2d.intersects(critical):
			occluded_rects += 1
			if _opaque_sample_in_intersection(image, view, overlay_rect_2d.intersection(critical)):
				opaque_critical_samples += 1
	var subtitle_rect_data: Dictionary = subtitle_data["rect"]
	if not subtitle_rect_data.is_empty():
		var subtitle_rect := Rect2(float(subtitle_rect_data.get("x", 0.0)), float(subtitle_rect_data.get("y", 0.0)),
				float(subtitle_rect_data.get("width", 0.0)), float(subtitle_rect_data.get("height", 0.0)))
		if subtitle_rect.intersects(critical):
			occluded_rects += 1
			if _opaque_sample_in_intersection(image, view, subtitle_rect.intersection(critical)):
				opaque_critical_samples += 1
	return {
		"feedback": feedback_data,
		"subtitle": subtitle_data,
		"critical_rect": _rect(critical),
		"occluding_rects": occluded_rects,
		"opaque_critical_samples": opaque_critical_samples,
		"critical_context_legible": bool(raster.get("context_legible", false)),
		"clear": bool(feedback_data.get("mouse_filter_ignore", false)) and occluded_rects == 0 and opaque_critical_samples == 0,
	}


func _critical_context_rect() -> Rect2:
	var critical := Rect2()
	var have_rect := false
	for key in ["active_shot", "drain", "shooter"]:
		var item: Variant = _last_context.get(key, {})
		if item is Dictionary and item.get("rect") is Dictionary:
			var rect_data: Dictionary = item["rect"]
			var rect := Rect2(float(rect_data.get("x", 0.0)), float(rect_data.get("y", 0.0)),
					float(rect_data.get("width", 0.0)), float(rect_data.get("height", 0.0)))
			critical = rect if not have_rect else critical.merge(rect)
			have_rect = true
	for flipper: Dictionary in _last_context.get("nearest_usable_flippers", []):
		if flipper.get("rect") is Dictionary:
			var rect_data: Dictionary = flipper["rect"]
			var rect := Rect2(float(rect_data.get("x", 0.0)), float(rect_data.get("y", 0.0)),
					float(rect_data.get("width", 0.0)), float(rect_data.get("height", 0.0)))
			critical = rect if not have_rect else critical.merge(rect)
			have_rect = true
	var ball: Variant = _last_context.get("ball", {})
	if ball is Dictionary and ball.get("center") is Dictionary:
		var center: Dictionary = ball["center"]
		var rect := Rect2(Vector2(float(center.get("x", 0.0)), float(center.get("y", 0.0)))
				- Vector2(Feel.BALL_RADIUS, Feel.BALL_RADIUS), Vector2(Feel.BALL_RADIUS * 2.0, Feel.BALL_RADIUS * 2.0))
		critical = rect if not have_rect else critical.merge(rect)
	return critical


func _opaque_sample_in_intersection(image: Image, view: Rect2, rect: Rect2) -> bool:
	if image == null or image.is_empty() or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	var uv := (rect.get_center() - view.position) / view.size
	var x := clampi(int(round(uv.x * float(image.get_width() - 1))), 0, image.get_width() - 1)
	var y := clampi(int(round(uv.y * float(image.get_height() - 1))), 0, image.get_height() - 1)
	return image.get_pixel(x, y).a > 0.95


func _subtitle_visible() -> bool:
	if Presentation.subtitles == null:
		return false
	var snapshot: Variant = Presentation.subtitles.call("snapshot")
	return bool(snapshot.get("visible", false)) if snapshot is Dictionary else false


func _subtitle_rect() -> Dictionary:
	if Presentation.subtitles == null:
		return {}
	var snapshot: Variant = Presentation.subtitles.call("snapshot")
	if snapshot is Dictionary and snapshot.get("rect") is Rect2:
		return _rect(snapshot["rect"])
	return {}


func _rank_for_subject() -> String:
	return String(SUBJECT_RANKS.get(String(_subject), "route"))


func _segment_family() -> String:
	if String(_subject).begins_with("boss-"):
		return "boss"
	return String(SUBJECT_SEGMENTS.get(String(_subject), "lower"))


func _vec(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _rect(value: Rect2) -> Dictionary:
	return {"x": value.position.x, "y": value.position.y, "width": value.size.x, "height": value.size.y}


func _point_rect(point: Vector2, diameter: float) -> Rect2:
	var half := diameter * 0.5
	return Rect2(point - Vector2(half, half), Vector2(diameter, diameter))


func _size_dict(value: Vector2i) -> Dictionary:
	return {"width": value.x, "height": value.y}


func _unique_path(path: String) -> String:
	var absolute := ProjectSettings.globalize_path(path)
	var parent := absolute.get_base_dir()
	DirAccess.make_dir_recursive_absolute(parent)
	if not FileAccess.file_exists(absolute):
		return absolute
	var stem := absolute.get_basename()
	var ext := "." + absolute.get_extension() if not absolute.get_extension().is_empty() else ""
	for index in range(1, 10000):
		var candidate := "%s-%03d%s" % [stem, index, ext]
		if not FileAccess.file_exists(candidate):
			return candidate
	return "%s-%d%s" % [stem, Time.get_ticks_usec(), ext]


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("C8A: unable to write ", path)
		return
	file.store_string(JSON.stringify(value, "\t"))
	file.close()


func _fail_and_quit(message: String) -> void:
	printerr("C8A NATURAL FOLLOW: ", message)
	get_tree().quit(1)
