class_name PresentationSafeArea
extends Node
## Converts physical display cutouts into the logical 1080-design canvas and adds a
## conservative guard for rounded glass. Full-bleed art ignores this service; critical UI
## uses margins()/apply_to_margin_container().

signal margins_changed(margins: Vector4)

const DEFAULT_CORNER_GUARD := 48.0
const MOBILE_PLATFORMS: PackedStringArray = ["Android", "iOS"]

var corner_guard: float = DEFAULT_CORNER_GUARD
var _cached := Vector4(-1.0, -1.0, -1.0, -1.0)
var _override_window := Vector2i.ZERO
var _override_safe := Rect2i()
var _override_guard: float = -1.0


func _ready() -> void:
	_parse_environment_override()
	get_viewport().size_changed.connect(_refresh)
	call_deferred(&"_refresh")


func margins() -> Vector4:
	var viewport_size := get_viewport().get_visible_rect().size
	var window_size := _override_window if _override_window != Vector2i.ZERO \
			else DisplayServer.window_get_size()
	if window_size.x <= 0 or window_size.y <= 0:
		window_size = Vector2i(maxi(1, int(viewport_size.x)), maxi(1, int(viewport_size.y)))
	var safe := _physical_safe_rect(window_size)
	# Rounded-glass compensation is a mobile presentation concern. Desktop windows are
	# rectangular, so retaining the guard there would silently change the authored layout
	# and make screenshot comparison noisy. Explicit debug overrides still exercise it.
	var guard := _override_guard if _override_guard >= 0.0 else (
			corner_guard if MOBILE_PLATFORMS.has(OS.get_name()) else 0.0)
	return calculate_margins(viewport_size, window_size, safe, guard)


func content_rect() -> Rect2:
	var m := margins()
	var size := get_viewport().get_visible_rect().size
	return Rect2(Vector2(m.x, m.y), Vector2(
			maxf(0.0, size.x - m.x - m.z), maxf(0.0, size.y - m.y - m.w)))


func apply_to_margin_container(container: MarginContainer, base: Vector4) -> void:
	if container == null:
		return
	var m := margins()
	container.add_theme_constant_override("margin_left", int(ceil(maxf(base.x, m.x))))
	container.add_theme_constant_override("margin_top", int(ceil(maxf(base.y, m.y))))
	container.add_theme_constant_override("margin_right", int(ceil(maxf(base.z, m.z))))
	container.add_theme_constant_override("margin_bottom", int(ceil(maxf(base.w, m.w))))


func set_debug_override(window_size: Vector2i, safe_rect: Rect2i,
		guard: float = DEFAULT_CORNER_GUARD) -> void:
	_override_window = window_size
	_override_safe = safe_rect
	_override_guard = maxf(guard, 0.0)
	_refresh()


func clear_debug_override() -> void:
	_override_window = Vector2i.ZERO
	_override_safe = Rect2i()
	_override_guard = -1.0
	_refresh()


func _refresh() -> void:
	var next := margins()
	if next.is_equal_approx(_cached):
		return
	_cached = next
	margins_changed.emit(next)


func _physical_safe_rect(window_size: Vector2i) -> Rect2i:
	if _override_window != Vector2i.ZERO:
		return _override_safe
	# Desktop safe areas describe the monitor rather than the project window. Treat desktop
	# windows as rectangular unless a test override is active.
	if not MOBILE_PLATFORMS.has(OS.get_name()):
		return Rect2i(Vector2i.ZERO, window_size)
	var reported := DisplayServer.get_display_safe_area()
	return reported if reported.size.x > 0 and reported.size.y > 0 \
			else Rect2i(Vector2i.ZERO, window_size)


func _parse_environment_override() -> void:
	if not ReleaseChannel.allow_development_hooks():
		return
	var raw := OS.get_environment("KINGPIN_SAFE_INSETS")
	if raw.is_empty():
		return
	var parts := raw.split(",")
	if parts.size() != 4:
		push_warning("KINGPIN_SAFE_INSETS expects left,top,right,bottom physical pixels")
		return
	var window_size := DisplayServer.window_get_size()
	var left := maxi(0, int(parts[0]))
	var top := maxi(0, int(parts[1]))
	var right := maxi(0, int(parts[2]))
	var bottom := maxi(0, int(parts[3]))
	var safe := Rect2i(left, top, maxi(0, window_size.x - left - right),
			maxi(0, window_size.y - top - bottom))
	var guard_raw := OS.get_environment("KINGPIN_CORNER_GUARD")
	var guard := float(guard_raw) if not guard_raw.is_empty() else DEFAULT_CORNER_GUARD
	set_debug_override(window_size, safe, guard)


static func calculate_margins(viewport_size: Vector2, window_size: Vector2i,
		safe_rect: Rect2i, guard: float = DEFAULT_CORNER_GUARD) -> Vector4:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0 \
			or window_size.x <= 0 or window_size.y <= 0:
		return Vector4(guard, guard, guard, guard)
	var full := Rect2i(Vector2i.ZERO, window_size)
	var safe := safe_rect.intersection(full)
	if safe.size.x <= 0 or safe.size.y <= 0:
		safe = full
	var sx := viewport_size.x / float(window_size.x)
	var sy := viewport_size.y / float(window_size.y)
	var left := float(safe.position.x) * sx
	var top := float(safe.position.y) * sy
	var right := float(window_size.x - safe.end.x) * sx
	var bottom := float(window_size.y - safe.end.y) * sy
	var max_x := viewport_size.x * 0.5
	var max_y := viewport_size.y * 0.5
	return Vector4(
			clampf(maxf(left, guard), 0.0, max_x),
			clampf(maxf(top, guard), 0.0, max_y),
			clampf(maxf(right, guard), 0.0, max_x),
			clampf(maxf(bottom, guard), 0.0, max_y))
