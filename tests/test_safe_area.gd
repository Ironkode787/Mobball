extends RefCounted


func run(t: TestCtx) -> void:
	var normal := PresentationSafeArea.calculate_margins(
			Vector2(1080, 1920), Vector2i(1080, 1920), Rect2i(0, 0, 1080, 1920), 48.0)
	_assert_margins(t, normal, Vector4(48, 48, 48, 48), "rounded glass guard")

	var notch := PresentationSafeArea.calculate_margins(
			Vector2(1080, 1920), Vector2i(1080, 1920), Rect2i(0, 96, 1080, 1824), 48.0)
	_assert_margins(t, notch, Vector4(48, 96, 48, 48), "top notch")

	var asymmetric := PresentationSafeArea.calculate_margins(
			Vector2(1080, 1920), Vector2i(1080, 1920), Rect2i(40, 100, 980, 1790), 48.0)
	_assert_margins(t, asymmetric, Vector4(48, 100, 60, 48), "asymmetric cutout")

	var expanded := PresentationSafeArea.calculate_margins(
			Vector2(1280, 1920), Vector2i(1080, 1920), Rect2i(54, 0, 972, 1920), 48.0)
	t.near(expanded.x, 64.0, 0.01, "physical left inset scales into expanded canvas")
	t.near(expanded.z, 64.0, 0.01, "physical right inset scales into expanded canvas")
	t.near(expanded.y, 48.0, 0.01, "logical corner guard stays stable")

	var invalid := PresentationSafeArea.calculate_margins(
			Vector2(1080, 1920), Vector2i(1080, 1920), Rect2i(4000, 4000, 10, 10), 48.0)
	_assert_margins(t, invalid, Vector4(48, 48, 48, 48), "invalid safe rect falls back")

	var crushed := PresentationSafeArea.calculate_margins(
			Vector2(1080, 1920), Vector2i(1080, 1920), Rect2i(900, 1700, 180, 220), 48.0)
	t.ok(crushed.x <= 540.0 and crushed.y <= 960.0, "unsafe input cannot invert content")


func _assert_margins(t: TestCtx, got: Vector4, want: Vector4, msg: String) -> void:
	t.near(got.x, want.x, 0.01, msg + " left")
	t.near(got.y, want.y, 0.01, msg + " top")
	t.near(got.z, want.z, 0.01, msg + " right")
	t.near(got.w, want.w, 0.01, msg + " bottom")
