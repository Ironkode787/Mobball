extends SceneTree
## Independent C8a sidecar validator.
##
## This process never instantiates the observer or the game. It validates an already-written
## sidecar, recomputes the image and current source hashes, and can apply in-memory negative
## mutations to exercise every rejection predicate without changing the evidence file.

const SCHEMA := "kingpin.c8a.natural_follow.v1"
const PHYSICS_HZ := 120
const MIN_SAMPLES := 600
const EXPECTED_LOGICAL := Vector2i(1080, 1920)
const PROFILES := {"compact": Vector2i(486, 864), "standard": Vector2i(1080, 1920),
	"narrow": Vector2i(720, 1280), "extra_tall": Vector2i(1080, 2400)}
const MODES := [&"color", &"large_text", &"reduced_motion", &"reduced_flash", &"grayscale",
	&"color_blind", &"haptics_off", &"subtitles_off", &"subtitles_on"]
const BLOCKED_MODES := [&"large_text", &"color_blind"]
const AUTHORITY_HASHES := {
	"observer": "res://tests/c8a_natural_follow_evidence.gd",
	"observer_scene": "res://tests/c8a_natural_follow_evidence.tscn",
	"validator": "res://tests/c8a_natural_follow_validator.gd",
	"capture_owner": "res://tools/shot_capture.gd",
	"main": "res://game/main.gd",
	"camera_rig": "res://game/core/camera_rig.gd",
	"progression_table": "res://game/table/segments/progression_table.gd",
}


func _initialize() -> void:
	var path := OS.get_environment("C8A_VALIDATE")
	if path.is_empty():
		printerr("C8A INDEPENDENT VALIDATOR: C8A_VALIDATE is required")
		quit(2)
		return
	var source := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(source)
	if not parsed is Dictionary:
		printerr("C8A INDEPENDENT VALIDATOR: malformed JSON")
		quit(1)
		return
	_apply_negative(parsed as Dictionary, OS.get_environment("C8A_VALIDATE_NEGATIVE"))
	var errors := _validate(parsed as Dictionary)
	var valid := errors.is_empty()
	print("C8A INDEPENDENT VALIDATOR: %s" % ("PASS" if valid else "FAIL"))
	for error: String in errors:
		print("  - ", error)
	quit(0 if valid else 1)


func _apply_negative(record: Dictionary, negative: String) -> void:
	match negative:
		"zero_dimensions":
			record["image_size"] = {"width": 0, "height": 0}
		"unknown_dimensions":
			record["requested_physical_size"] = {}
		"missing_image_hash":
			(record.get("image", {}) as Dictionary)["sha256"] = ""
		"missing_source_hash":
			(record.get("source", {}) as Dictionary)["source_sha256"] = ""
		"missing_camera_samples":
			(record.get("transition_trace", {}) as Dictionary).erase("camera_samples")
		"short_camera_samples":
			(record.get("transition_trace", {}) as Dictionary)["camera_samples"] = []
		"missing_context":
			record.erase("context")
		"parked_static":
			(record.get("predicates", {}) as Dictionary)["no_parked_static_evidence"] = false
		"placeholder":
			(record.get("source", {}) as Dictionary)["fixture"] = "placeholder"
		"unsupported_pass":
			record["mode"] = "large_text"
			record["status"] = "pass"
		"haptics_nonzero":
			record["mode"] = "haptics_off"
			(record.get("accessibility", {}) as Dictionary)["haptics_events"] = 1
		"stale_source_hash":
			(record.get("source", {}) as Dictionary)["source_hashes"]["observer"] = "stale"
		"seam_false":
			(record.get("transition_trace", {}) as Dictionary)["max_seam_exposure_frames"] = 1
			(record.get("predicates", {}) as Dictionary)["seam_free"] = false
		"paint_envelope_false":
			var seam_raster: Dictionary = record.get("transition_trace", {}).get("raster_inspection", {})
			seam_raster["paint_envelope"] = false
			seam_raster["transparent_edge_components"] = 1
			(record.get("predicates", {}) as Dictionary)["raster_paint_envelope"] = false
		"overlay_false":
			(record.get("predicates", {}) as Dictionary)["overlay_clear"] = false
		"reduced_legibility_false":
			(record.get("predicates", {}) as Dictionary)["reduced_mode_legible"] = false
		"context_raster_false":
			var context_raster: Dictionary = record.get("transition_trace", {}).get("raster_inspection", {})
			context_raster["context_legible"] = false
			(record.get("predicates", {}) as Dictionary)["context_raster_legible"] = false


func _validate(record: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var serialized := JSON.stringify(record)
	for token in ["...", "TODO", "placeholder", "unknown", "UNKNOWN"]:
		if serialized.find(token) >= 0:
			errors.append("literal placeholder token: %s" % token)
	var status := String(record.get("status", ""))
	var mode := String(record.get("mode", ""))
	if String(record.get("schema", "")) != SCHEMA:
		errors.append("schema mismatch")
	if not MODES.has(StringName(mode)):
		errors.append("unknown mode")
	if status == "blocked_capability":
		if not BLOCKED_MODES.has(StringName(mode)):
			errors.append("blocked status is only valid for large_text/color_blind")
		if String(record.get("blocked_reason", "")).is_empty():
			errors.append("blocked capability has no measured reason")
		return errors
	if status != "pass" and status != "diagnostic":
		errors.append("unknown status")
	if status == "pass" and BLOCKED_MODES.has(StringName(mode)):
		errors.append("unsupported capability mislabeled pass")
	for key in ["requested_physical_size", "actual_physical_size", "logical_viewport", "image_size"]:
		var d: Variant = record.get(key, {})
		if not _positive_dimensions(d):
			errors.append("zero/unknown dimensions: %s" % key)
	var requested: Dictionary = record.get("requested_physical_size", {})
	var actual: Dictionary = record.get("actual_physical_size", {})
	var profile := String(record.get("profile", ""))
	if not PROFILES.has(profile):
		errors.append("unknown profile")
	elif requested.get("width", 0) != PROFILES[profile].x or requested.get("height", 0) != PROFILES[profile].y:
		errors.append("requested dimensions do not match profile")
	if status == "pass" and requested != actual:
		errors.append("pass claims a host-clamped physical size")
	var logical: Dictionary = record.get("logical_viewport", {})
	if logical.get("width", 0) != EXPECTED_LOGICAL.x or logical.get("height", 0) != EXPECTED_LOGICAL.y:
		errors.append("logical viewport is not 1080x1920")
	var safe: Variant = record.get("safe_area", {})
	if not safe is Dictionary or not _positive_dimensions({"width": float(safe.get("corner_guard", 0.0)), "height": 1.0}):
		errors.append("missing safe-area corner guard")
	var raw: Variant = (safe as Dictionary).get("raw_insets_physical", {}) if safe is Dictionary else {}
	if not raw is Dictionary or not _nonnegative_insets(raw):
		errors.append("missing/invalid safe insets")
	var image: Variant = record.get("image", {})
	if not image is Dictionary or String((image as Dictionary).get("sha256", "")).is_empty():
		errors.append("missing image hash")
	else:
		var image_path := String((image as Dictionary).get("path", ""))
		if image_path.is_empty() or not FileAccess.file_exists(image_path):
			errors.append("original PNG missing")
		else:
			var loaded := Image.load_from_file(image_path)
			if loaded == null or loaded.is_empty():
				errors.append("original PNG unreadable")
			elif loaded.get_width() != int((image as Dictionary).get("width", 0)) or loaded.get_height() != int((image as Dictionary).get("height", 0)):
				errors.append("image dimensions do not match sidecar")
			if FileAccess.get_sha256(image_path) != String((image as Dictionary).get("sha256", "")):
				errors.append("image hash does not match original PNG")
	var source: Variant = record.get("source", {})
	if not source is Dictionary or String((source as Dictionary).get("source_sha256", "")).is_empty():
		errors.append("missing source hash")
	else:
		if String((source as Dictionary).get("source_sha256", "")) != FileAccess.get_sha256(AUTHORITY_HASHES["observer"]):
			errors.append("observer source hash is stale")
		var source_hashes: Variant = (source as Dictionary).get("source_hashes", {})
		if not source_hashes is Dictionary:
			errors.append("missing source hash map")
		else:
			for key: String in AUTHORITY_HASHES:
				if String((source_hashes as Dictionary).get(key, "")) != FileAccess.get_sha256(AUTHORITY_HASHES[key]):
					errors.append("source hash mismatch: %s" % key)
	var godot_text := String(source.get("godot", "")) if source is Dictionary else ""
	if godot_text.is_empty():
		errors.append("missing Godot provenance")
	if source is Dictionary and (String(source.get("host", "")).is_empty() or String(source.get("rendering_driver", "")).is_empty() or not source.has("seed")):
		errors.append("incomplete runtime provenance")
	var camera: Variant = record.get("camera", {})
	if not camera is Dictionary or String((camera as Dictionary).get("mode", "")) != "natural_follow" or not bool((camera as Dictionary).get("follow_enabled", false)) or not bool((camera as Dictionary).get("auto_bounds", false)):
		errors.append("camera is not truthful natural follow")
	var trace: Variant = record.get("transition_trace", {})
	if not trace is Dictionary:
		errors.append("missing transition trace")
	else:
		if int((trace as Dictionary).get("physics_hz", 0)) != PHYSICS_HZ:
			errors.append("physics sample rate is not 120 Hz")
		var frames := int((trace as Dictionary).get("frames_sampled", 0))
		if frames < MIN_SAMPLES:
			errors.append("fewer than 600 physics samples")
		var cameras: Variant = (trace as Dictionary).get("camera_samples", null)
		if not cameras is Array or cameras.is_empty():
			errors.append("missing camera samples")
		elif (cameras as Array).size() != frames:
			errors.append("camera sample count does not match frames_sampled")
		var pixels: Variant = (trace as Dictionary).get("viewport_pixel_samples", null)
		if not pixels is Array or pixels.is_empty():
			errors.append("missing viewport pixel samples")
		if int((trace as Dictionary).get("max_ball_out_frames", -1)) != 0:
			errors.append("ball was outside the view")
		if int((trace as Dictionary).get("max_void_frames", -1)) != 0:
			errors.append("void frames observed")
		if int((trace as Dictionary).get("max_seam_exposure_frames", -1)) != 0:
			errors.append("seam exposure observed")
		var raster: Variant = (trace as Dictionary).get("raster_inspection", {})
		if not raster is Dictionary or not bool((raster as Dictionary).get("paint_envelope", false)) or int((raster as Dictionary).get("transparent_edge_components", -1)) != 0 or int((raster as Dictionary).get("transparent_pixels", -1)) != 0 or int((raster as Dictionary).get("edge_samples", 0)) <= 0 or int((raster as Dictionary).get("non_background_pixels", 0)) <= int((image as Dictionary).get("width", 0)) * int((image as Dictionary).get("height", 0)) / 100 or not bool((raster as Dictionary).get("context_legible", false)):
			errors.append("raster paint/connected-region proof is missing")
	var overlay: Variant = record.get("overlay_inspection", {})
	if not overlay is Dictionary or not bool((overlay as Dictionary).get("clear", false)) or not bool((overlay as Dictionary).get("critical_context_legible", false)) or not bool(((overlay as Dictionary).get("feedback", {}) as Dictionary).get("mouse_filter_ignore", false)) or int((overlay as Dictionary).get("occluding_rects", -1)) != 0 or int((overlay as Dictionary).get("opaque_critical_samples", -1)) != 0:
		errors.append("overlay inspection reports critical obstruction")
	var context: Variant = record.get("context", {})
	if not context is Dictionary or not bool((context as Dictionary).get("bounds_nonzero", false)) or not bool((context as Dictionary).get("visible_in_view", false)):
		errors.append("missing/non-visible critical context")
	else:
		var ball: Variant = (context as Dictionary).get("ball", {})
		if not ball is Dictionary or not bool((ball as Dictionary).get("valid", false)) or String((ball as Dictionary).get("id", "")).is_empty() or not bool((ball as Dictionary).get("visible", false)):
			errors.append("missing live visible ball context")
		var shot: Variant = (context as Dictionary).get("active_shot", {})
		var route: Variant = (context as Dictionary).get("subject_route", {})
		if not shot is Dictionary or String((shot as Dictionary).get("status", "")) != "active":
			errors.append("missing active shot context")
		if not route is Dictionary or not bool((route as Dictionary).get("matches_observed_route", false)) or String((route as Dictionary).get("status", "")) != "canonical":
			errors.append("route is not canonical observed route")
		elif not shot is Dictionary or String((shot as Dictionary).get("id", "")) != String((route as Dictionary).get("observed", "")) or String(record.get("shot", "")) != String((route as Dictionary).get("observed", "")):
			errors.append("sidecar shot is not the observed route identity")
		var flippers: Variant = (context as Dictionary).get("nearest_usable_flippers", [])
		if not flippers is Array or flippers.size() < 2:
			errors.append("missing usable flipper context")
		for key in ["drain", "shooter"]:
			var item: Variant = (context as Dictionary).get(key, {})
			if not item is Dictionary or not _positive_dimensions((item as Dictionary).get("rect", {})):
				errors.append("missing %s context" % key)
		var route_trace: Variant = (trace as Dictionary) if trace is Dictionary else {}
		var checkpoints: Variant = (route_trace as Dictionary).get("route_checkpoints", []) if route_trace is Dictionary else []
		var route_ids: Variant = (route_trace as Dictionary).get("route_ids", []) if route_trace is Dictionary else []
		if not checkpoints is Array or not route_ids is Array:
			errors.append("missing route checkpoint trace")
		else:
			var labels := {}
			for checkpoint: Variant in checkpoints:
				if checkpoint is Dictionary:
					labels[String((checkpoint as Dictionary).get("label", ""))] = true
			var expected_route := String((shot as Dictionary).get("expected_id", "")) if shot is Dictionary else ""
			if expected_route.is_empty() or not route_ids.has(expected_route):
				errors.append("expected route missing from checkpoint trace")
			for label in ["pre_transition", "active_flight", "danger_or_return", "settled"]:
				if not labels.has(label):
					errors.append("missing route checkpoint: %s" % label)
	var predicates: Variant = record.get("predicates", {})
	if not predicates is Dictionary:
		errors.append("missing predicates")
	else:
		for key in ["vertical_contained", "ball_continuous", "context_simultaneous", "overlay_clear", "reduced_mode_legible", "raster_paint_envelope", "context_raster_legible", "seam_free", "no_parked_static_evidence", "route_checkpoints_complete"]:
			if not bool((predicates as Dictionary).get(key, false)):
				errors.append("false objective predicate: %s" % key)
		if not bool((predicates as Dictionary).get("horizontal_strict_contained", false)) and String((predicates as Dictionary).get("horizontal_status", "")) != "UNSATISFIABLE/OPEN":
			errors.append("horizontal containment must remain UNSATISFIABLE/OPEN")
	var accessibility: Variant = record.get("accessibility", {})
	if mode == "haptics_off" and (not accessibility is Dictionary or int((accessibility as Dictionary).get("haptics_events", -1)) != 0):
		errors.append("haptics_off emitted haptic events")
	if status == "pass" and (not predicates is Dictionary or not bool((predicates as Dictionary).get("ball_continuous", false))):
		errors.append("pass mislabeled with lost/out-of-view ball")
	return errors


func _positive_dimensions(value: Variant) -> bool:
	return value is Dictionary and float((value as Dictionary).get("width", 0.0)) > 0.0 and float((value as Dictionary).get("height", 0.0)) > 0.0


func _nonnegative_insets(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["left", "top", "right", "bottom"]:
		if float((value as Dictionary).get(key, -1.0)) < 0.0:
			return false
	return true
