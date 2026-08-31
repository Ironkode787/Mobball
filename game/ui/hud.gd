class_name GameHUD
extends CanvasLayer
## The real HUD (specs/m1-hook.md Lane 1): dirty, clean, Heat with its band ticks, Respect,
## the Night number and the combo flash — plus who is on the table right now, because the
## balls are guys (docs/01 §4).
##
## M2 hangs the modes under the strip: the Wire's tote board, the Collection Round's clock,
## whether the back room is lit and whether the Family Meeting is running. Each line only
## exists while it has something to say — a mode line that is always there is furniture.
##
## Signal-driven for state, per-frame for clocks (a countdown is a per-frame value by nature,
## as is the plunger charge).

const STRIP_H := 168.0
## Tall phones put the unsafe top glass behind the table art and reserve only this shallow,
## two-row panel below it for information. The cutout must not turn into a black spacer.
const COMPACT_STRIP_H := 104.0
const COMPACT_MONEY_FONT := 27
const HEAT_W := 470.0
const HEAT_H := 26.0
## B4's Federal policy is presentation-only: the Heat dial keeps the model's absolute
## 0..200 scale when the Federal stage is enabled. Ordinary Heat remains 0..100.
const FEDERAL_HEAT_PRESENTATION_MAX := Rates.HEAT_FEDERAL_MAX
const SHOOTER_LANE_LEFT := 940.0
const FLIPPER_REGION_TOP := 1520.0
const COMBO_FLASH := 1.1
## How long Manny's collect stays on the mode strip.
const AUTO_COLLECT_FLASH := 2.5
## Where the mode lines hang, and how tall each one is.
const MODES_TOP := STRIP_H + 16.0
const MODE_H := 34.0
const MODE_ROWS := 11

var night_controller: NightController = null

var _dirty: Label = null
var _clean: Label = null
var _night: Label = null
var _respect: Label = null
var _guy: Label = null
var _combo: Label = null
var _heat: HeatBar = null
var _charge: PlungerLane = null
var _star: StarBadge = null
var _strip: ColorRect = null
var _rule: ColorRect = null
var _chrome: HudChrome = null
var _guy_meta: Label = null
var _respect_hint: Label = null
var _respect_meter: RespectMeter = null
var _objective: Label = null
var _objective_backdrop: ColorRect = null
var _combo_left: float = 0.0
var _modes: VBoxContainer = null
var _wire: Label = null
var _collect: Label = null
var _meeting: Label = null
var _casino: Label = null
var _boss: Label = null
var _federal: Label = null
var _empire: Label = null
var _heist: Label = null
var _docks: Label = null
var _city: Label = null
var _ritual: Label = null
## Manny's collect, flashed for a beat so an off-screen earner is still visible.
var _flash: String = ""
var _flash_left: float = 0.0
var _compact := false
var _profile_id: StringName = &"standard"
var _logical_viewport := Vector2.ZERO
var _safe_content := Rect2()
var _requested_window := Vector2i.ZERO
var _actual_window := Vector2i.ZERO
var _geometry_contract: Dictionary = {}
var _selected_objective_source: StringName = &"fallback"
var _priority_trace := PackedStringArray()


func _ready() -> void:
	layer = 10
	_strip = ColorRect.new()
	_strip.name = "Strip"
	_strip.color = Color(Presentation.theme.ink, 0.94)
	_strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_strip.offset_bottom = STRIP_H
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)

	_chrome = HudChrome.new()
	_chrome.name = "HudChrome"
	_chrome.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chrome)

	_rule = ColorRect.new()
	_rule.color = Presentation.theme.brass.darkened(0.35)
	_rule.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_rule.offset_top = STRIP_H
	_rule.offset_bottom = STRIP_H + 3.0
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rule)

	_dirty = _add_label(Vector2(26.0, 14.0), PaperKit.FONT_BIG, Presentation.theme.dirty)
	_clean = _add_label(Vector2(26.0, 74.0), PaperKit.FONT_BIG, Presentation.theme.clean)
	_night = _add_label(Vector2(0.0, 14.0), PaperKit.FONT_SMALL, Presentation.theme.newsprint,
			HORIZONTAL_ALIGNMENT_RIGHT)
	_respect = _add_label(Vector2(0.0, 60.0), PaperKit.FONT_BIG, Presentation.theme.brass,
			HORIZONTAL_ALIGNMENT_RIGHT)
	_respect_hint = _add_label(Vector2.ZERO, PaperKit.FONT_SMALL,
			Presentation.theme.newsprint.darkened(0.22), HORIZONTAL_ALIGNMENT_RIGHT)
	_guy = _add_label(Vector2(26.0, 124.0), PaperKit.FONT_SMALL, Presentation.theme.newsprint)
	_guy.clip_text = false
	_guy_meta = _add_label(Vector2.ZERO, PaperKit.FONT_SMALL,
			Presentation.theme.newsprint.darkened(0.30))
	_guy_meta.clip_text = false

	_star = StarBadge.new()
	_star.position = Vector2(1080.0 - 62.0, 68.0)
	_star.size = Vector2(34.0, 34.0)
	_star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_star)

	_heat = HeatBar.new()
	_heat.position = Vector2(540.0 - HEAT_W * 0.5, 128.0)
	_heat.size = Vector2(HEAT_W, HEAT_H)
	_heat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_heat)

	_respect_meter = RespectMeter.new()
	_respect_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_respect_meter)

	_combo = _add_label(Vector2(0.0, 210.0), PaperKit.FONT_HUGE, Presentation.theme.brass,
			HORIZONTAL_ALIGNMENT_CENTER)
	_combo.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_combo.offset_top = 210.0
	_combo.offset_bottom = 320.0
	_combo.modulate.a = 0.0
	# Phase 3 owns combo feedback centrally; retaining this second giant copy made the phone
	# header feel taller even though it was technically outside the strip.
	_combo.visible = false

	_charge = PlungerLane.new()
	_charge.name = "PlungerLane"
	_charge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_charge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_charge)

	_build_modes()
	_apply_safe_area()
	Presentation.safe.margins_changed.connect(_on_safe_margins_changed)

	Game.wallet.dirty_changed.connect(_on_dirty)
	Game.wallet.clean_changed.connect(_on_clean)
	Game.heat.heat_changed.connect(_on_heat)
	Events.combo_changed.connect(_on_combo)
	Events.respect_changed.connect(_on_respect)
	Events.rank_changed.connect(_on_rank)
	Events.night_started.connect(_on_night)
	Events.guy_pinched.connect(_on_guy_changed)
	Events.plunger_charge_changed.connect(_on_charge)
	Game.auto_collected.connect(_on_auto_collected)
	refresh()


func _on_safe_margins_changed(_margins: Vector4) -> void:
	_apply_safe_area()


func _apply_safe_area() -> void:
	if _strip == null:
		return
	var service_margins := Presentation.safe.margins()
	var logical_rect := get_viewport().get_visible_rect()
	_logical_viewport = logical_rect.size
	# PresentationSafeArea lives on the process-wide root, while evidence fixtures may host
	# this HUD in a SubViewport. Intersecting with this HUD's logical viewport preserves the
	# service's cutout margins without importing a host-clamped width into local geometry.
	_safe_content = Presentation.safe.content_rect().intersection(logical_rect)
	if _safe_content.size.x <= 0.0 or _safe_content.size.y <= 0.0:
		# The safe service falls back to guarded margins for an unready viewport. Keep a
		# positive contract while the first resize settles, then refresh on its signal.
		_safe_content = Rect2(Vector2(service_margins.x, service_margins.y), Vector2(
				maxf(_logical_viewport.x - service_margins.x - service_margins.z, 1.0),
				maxf(_logical_viewport.y - service_margins.y - service_margins.w, 1.0)))
	var m := Vector4(_safe_content.position.x, _safe_content.position.y,
			maxf(_logical_viewport.x - _safe_content.end.x, 0.0),
			maxf(_logical_viewport.y - _safe_content.end.y, 0.0))
	_actual_window = DisplayServer.window_get_size()
	if _actual_window.x <= 0 or _actual_window.y <= 0:
		_actual_window = Vector2i(maxi(1, int(_logical_viewport.x)),
				maxi(1, int(_logical_viewport.y)))
	_requested_window = _requested_capture_size(_actual_window)
	var window_width := float(_actual_window.x)
	# The project keeps a 1080x1920 logical canvas on every phone. Profile selection therefore
	# uses the physical window width, while layout uses the actual logical viewport and safe
	# content rectangle. In particular, host-clamped height never silently changes profile.
	var requested_profile := OS.get_environment("KINGPIN_HUD_PROFILE").to_lower()
	if ReleaseChannel.allow_development_hooks() \
			and (requested_profile == "compact" or requested_profile == "standard"):
		_compact = requested_profile == "compact"
	else:
		_compact = window_width < 720.0
	_profile_id = &"compact" if _compact else &"standard"
	var profile := Presentation.theme.layout_profile(_profile_id)
	var viewport_width := _logical_viewport.x
	var content_h := COMPACT_STRIP_H if _compact else STRIP_H
	var header_bottom := content_h + m.y
	# On cutout phones the unsafe cap is useful full-bleed playfield, not HUD padding. Only
	# the readable two-row panel darkens the table, and even that remains smoked rather than
	# opaque. Desktop keeps the authored cabinet strip.
	_strip.offset_top = m.y if _compact else 0.0
	_strip.offset_bottom = header_bottom
	_strip.color = Color(Presentation.theme.ink, 0.90) if _compact else Color(Presentation.theme.ink, 0.96)
	_chrome.offset_top = _strip.offset_top
	_chrome.offset_bottom = _strip.offset_bottom
	_chrome.configure(_compact, m, profile)
	_rule.offset_top = header_bottom
	_rule.offset_bottom = header_bottom + 3.0

	if _compact:
		_apply_compact_layout(m, viewport_width, header_bottom)
	else:
		_apply_standard_layout(m, viewport_width)
	_on_respect(Game.respect)

	_combo.offset_left = m.x
	_combo.offset_right = -m.z
	_combo.offset_top = m.y + 210.0
	_combo.offset_bottom = m.y + 320.0
	_modes.offset_left = m.x + 26.0
	_modes.offset_right = -(m.z + 26.0)
	_modes.offset_top = header_bottom + (8.0 if _compact else 12.0)
	_modes.offset_bottom = _modes.offset_top + (48.0 if _compact else 56.0)
	_objective_backdrop.offset_left = m.x + 18.0
	_objective_backdrop.offset_right = -(m.z + 18.0)
	_objective_backdrop.offset_top = _modes.offset_top - 4.0
	_objective_backdrop.offset_bottom = _modes.offset_bottom + 2.0
	# Keep the readable copy itself inside the reserved band. It is a direct HUD child rather
	# than a VBox row so a long producer string cannot turn its minimum width into a one-pixel
	# column or its wrapped minimum height into an unbounded stack.
	_objective.offset_left = m.x + 26.0
	_objective.offset_right = -(m.z + 26.0)
	_objective.offset_top = _modes.offset_top + 4.0
	_objective.offset_bottom = _modes.offset_bottom - 2.0
	_charge.offset_right = -(m.z + (18.0 if _compact else 28.0))
	_charge.offset_left = -(m.z + (18.0 if _compact else 28.0) + (44.0 if _compact else 176.0))
	_charge.offset_top = -(m.w + (224.0 if _compact else 320.0))
	_charge.offset_bottom = -(m.w + 12.0)
	_charge.configure(_compact)
	_update_geometry_contract(m, profile, header_bottom)


func _requested_capture_size(actual: Vector2i) -> Vector2i:
	# Capture fixtures may state their requested physical size without changing the runtime
	# window. This keeps host-clamped diagnostics honest and defaults to the actual window.
	var raw := OS.get_environment("KINGPIN_REQUESTED_SIZE")
	if raw.is_empty():
		raw = OS.get_environment("KINGPIN_CAPTURE_REQUESTED_SIZE")
	if raw.is_empty():
		return actual
	var parts := raw.to_lower().replace(" ", "").split("x")
	if parts.size() != 2:
		return actual
	var width := int(parts[0])
	var height := int(parts[1])
	return Vector2i(width, height) if width > 0 and height > 0 else actual


func _update_geometry_contract(m: Vector4, profile: Dictionary, header_bottom: float) -> void:
	if _strip == null or _charge == null:
		return
	var strip := _strip.get_rect()
	var lane := Rect2(SHOOTER_LANE_LEFT, 0.0, maxf(_logical_viewport.x - SHOOTER_LANE_LEFT, 0.0),
			_logical_viewport.y)
	var flipper := Rect2(0.0, FLIPPER_REGION_TOP, _logical_viewport.x,
			maxf(_logical_viewport.y - FLIPPER_REGION_TOP, 0.0))
	var clean_x := maxf(m.x, 48.0) + 176.0
	var anchors := {
			"safe_content": _safe_content,
			"strip": strip,
			"strip_bounds": strip,
			"header_bottom": header_bottom,
			"guy": _global_control_rect(_guy),
			"heat": _global_control_rect(_heat),
			"respect": _global_control_rect(_respect),
			"objective": _global_control_rect(_objective_backdrop),
			"objective_label": _global_control_rect(_objective),
			"plunger": _global_control_rect(_charge),
			"shooter_lane": lane,
			"lane_clearance": lane,
			"flipper_region": flipper,
			"flipper_clearance": flipper,
			"clean_destination": Vector2(clean_x, _clean.get_rect().get_center().y),
	}
	_geometry_contract = {
			"profile": _profile_id,
			"profile_config": profile.duplicate(true),
			"requested_physical_size": _requested_window,
			"actual_physical_size": _actual_window,
			"logical_viewport": _logical_viewport,
			"safe_margins": m,
			"safe_content": _safe_content,
			"anchors": anchors,
			"federal_heat_policy": &"absolute_0_200",
			"federal_heat_max": FEDERAL_HEAT_PRESENTATION_MAX,
			"shooter_lane_left": SHOOTER_LANE_LEFT,
			"flipper_region_top": FLIPPER_REGION_TOP,
			"clean_destination_x": clean_x,
	}


func _global_control_rect(control: Control) -> Rect2:
	return control.get_global_rect() if control != null else Rect2()


func _apply_compact_layout(m: Vector4, viewport_width: float, _header_bottom: float) -> void:
	var safe_w := maxf(viewport_width - m.x - m.z, 1.0)
	var left := m.x + 12.0
	var right := viewport_width - m.z - 12.0
	# Keep the visible Clean value over the same horizontal destination used by the
	# gameplay feedback flight. The producer/arithmetic remains owned by gameplay;
	# this only makes the presentation land on the value the player reads.
	var clean_destination := maxf(m.x, 48.0) + 176.0
	var second_start := clampf(clean_destination, left + 132.0, right - 168.0)
	var first_end := second_start - 14.0
	var second_end := minf(second_start + 164.0, m.x + safe_w * 0.575)
	var status_start := m.x + safe_w * 0.595
	_dirty.add_theme_font_size_override("font_size", COMPACT_MONEY_FONT)
	_dirty.offset_left = left
	_dirty.offset_right = -(viewport_width - first_end)
	_dirty.offset_top = m.y + 5.0
	_dirty.offset_bottom = m.y + 42.0
	_dirty.clip_text = false
	_clean.add_theme_font_size_override("font_size", COMPACT_MONEY_FONT)
	_clean.offset_left = second_start
	_clean.offset_right = -(viewport_width - second_end)
	_clean.offset_top = m.y + 5.0
	_clean.offset_bottom = m.y + 42.0
	_clean.clip_text = false
	_night.offset_left = status_start
	_night.offset_right = -(m.z + 12.0)
	_night.offset_top = m.y + 8.0
	_night.offset_bottom = m.y + 38.0
	_night.add_theme_font_size_override("font_size", 18)
	_night.clip_text = false

	_guy.offset_left = left
	_guy.offset_right = -(m.x + safe_w * 0.43)
	_guy.offset_top = m.y + 53.0
	_guy.offset_bottom = m.y + 78.0
	# Label's font minimum is taller than the compact header slot on this renderer. Pin the
	# actual control to the accepted 25 px Guy row instead of letting that minimum overlap the
	# metadata row below it.
	_guy.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_guy.position = Vector2(left, m.y + 53.0)
	_guy.add_theme_font_size_override("font_size", 17)
	_guy.add_theme_constant_override("line_spacing", 0)
	_guy.size = Vector2(maxf(viewport_width - (m.x + safe_w * 0.43) - left, 1.0), 25.0)
	_guy_meta.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_guy_meta.position = Vector2(left, m.y + 76.0)
	_guy_meta.add_theme_font_size_override("font_size", 15)
	_guy_meta.add_theme_constant_override("line_spacing", 0)
	_guy_meta.size = Vector2(maxf(viewport_width - (m.x + safe_w * 0.43) - left, 1.0), 23.0)
	var heat_x := m.x + safe_w * 0.455
	var heat_w := clampf(safe_w * 0.305, 106.0, 148.0)
	_heat.position = Vector2(heat_x, m.y + 55.0)
	_heat.size = Vector2(heat_w, 43.0)
	_heat.configure(true)
	var respect_x := m.x + safe_w * 0.78
	_respect.add_theme_font_size_override("font_size", 17)
	_respect.offset_left = respect_x
	_respect.offset_right = -(m.z + 34.0)
	_respect.offset_top = m.y + 53.0
	_respect.offset_bottom = m.y + 77.0
	_respect.clip_text = false
	_respect_hint.add_theme_font_size_override("font_size", 14)
	_respect_hint.offset_left = respect_x
	_respect_hint.offset_right = -(m.z + 34.0)
	_respect_hint.offset_top = m.y + 75.0
	_respect_hint.offset_bottom = m.y + 98.0
	_respect_hint.clip_text = false
	_respect_meter.position = Vector2(respect_x, m.y + 96.0)
	_respect_meter.size = Vector2(maxf(40.0, right - 34.0 - respect_x), 5.0)
	_respect_meter.configure(true)
	_star.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_star.offset_left = -(m.z + 29.0)
	_star.offset_right = -(m.z + 7.0)
	_star.offset_top = m.y + 54.0
	_star.offset_bottom = m.y + 76.0


func _apply_standard_layout(m: Vector4, viewport_width: float) -> void:
	var safe_w := maxf(viewport_width - m.x - m.z, 1.0)
	var left := m.x + 26.0
	# GameplayFeedback.destination_for() intentionally stays untouched. Match its
	# preserved x destination here so the incoming Clean amount resolves to the
	# value instead of an unrelated gap in the header.
	var clean_destination := maxf(m.x, 48.0) + 176.0
	var clean_start := clampf(clean_destination, left + 178.0, viewport_width - m.z - 270.0)
	var dirty_end := clean_start - 16.0
	var status_start := m.x + safe_w * 0.69
	var clean_end := minf(clean_start + 250.0, status_start - 28.0)
	_dirty.add_theme_font_size_override("font_size", PaperKit.FONT_BIG)
	_clean.add_theme_font_size_override("font_size", PaperKit.FONT_BIG)
	_respect.add_theme_font_size_override("font_size", 28)

	_dirty.offset_left = left
	_dirty.offset_right = -(viewport_width - dirty_end)
	_dirty.offset_top = m.y + 14.0
	_dirty.offset_bottom = m.y + 60.0
	_clean.offset_left = clean_start
	_clean.offset_right = -(viewport_width - clean_end)
	_clean.offset_top = m.y + 14.0
	_clean.offset_bottom = m.y + 60.0
	_night.offset_left = status_start
	_night.offset_right = -(m.z + 26.0)
	_night.offset_top = m.y + 18.0
	_night.offset_bottom = m.y + 48.0
	_night.add_theme_font_size_override("font_size", 24)
	_respect.offset_left = viewport_width * 0.75
	_respect.offset_right = -(m.z + 66.0)
	_respect.offset_top = m.y + 84.0
	_respect.offset_bottom = m.y + 120.0
	_respect_hint.add_theme_font_size_override("font_size", 20)
	_respect_hint.offset_left = viewport_width * 0.75
	_respect_hint.offset_right = -(m.z + 66.0)
	_respect_hint.offset_top = m.y + 117.0
	_respect_hint.offset_bottom = m.y + 148.0

	_star.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_star.offset_left = -(m.z + 54.0)
	_star.offset_right = -(m.z + 20.0)
	_star.offset_top = m.y + 86.0
	_star.offset_bottom = m.y + 120.0

	var heat_x := viewport_width * 0.37
	var heat_w := minf(HEAT_W, viewport_width * 0.34)
	_heat.position = Vector2(heat_x, m.y + 92.0)
	_heat.size = Vector2(heat_w, 56.0)
	_heat.configure(false)
	_guy.offset_left = m.x + 26.0
	# _guy is TOP_WIDE anchored, so offset_right is measured from the viewport's
	# right edge. Keep the identity's actual right edge before the Heat module; the
	# existing fit pass then preserves long names without crossing that boundary.
	_guy.offset_right = -(viewport_width - (heat_x - 28.0))
	_guy.offset_top = m.y + 88.0
	_guy.offset_bottom = m.y + 124.0
	_guy.add_theme_font_size_override("font_size", 27)
	_guy_meta.offset_left = m.x + 26.0
	_guy_meta.offset_right = -(viewport_width - (heat_x - 28.0))
	_guy_meta.offset_top = m.y + 120.0
	_guy_meta.offset_bottom = m.y + 150.0
	_guy_meta.add_theme_font_size_override("font_size", 20)
	_respect_meter.position = Vector2(viewport_width * 0.75, m.y + 150.0)
	_respect_meter.size = Vector2(maxf(80.0, viewport_width * 0.18), 7.0)
	_respect_meter.configure(false)


func compact_layout() -> bool:
	return _compact


func strip_rect() -> Rect2:
	return _strip.get_rect() if _strip != null else Rect2()


## B5 consumes this stable profile identifier; it is selected from the physical width only.
func hud_profile() -> StringName:
	return _profile_id


func profile_id() -> StringName:
	return _profile_id


## These accessors intentionally report logical coordinates, not the host window's raster size.
func logical_viewport_size() -> Vector2:
	return _logical_viewport


func safe_content_rect() -> Rect2:
	return _safe_content


func requested_physical_size() -> Vector2i:
	return _requested_window


func requested_window_size() -> Vector2i:
	return _requested_window


func actual_physical_size() -> Vector2i:
	return _actual_window


func actual_window_size() -> Vector2i:
	return _actual_window


func geometry_contract() -> Dictionary:
	return _geometry_contract.duplicate(true)


func hud_geometry() -> Dictionary:
	return geometry_contract()


func geometry_snapshot() -> Dictionary:
	return geometry_contract()


func coach_anchors() -> Dictionary:
	var anchors: Variant = _geometry_contract.get("anchors", {})
	return (anchors as Dictionary).duplicate(true) if anchors is Dictionary else {}


func objective_source() -> StringName:
	return _selected_objective_source


func priority_trace() -> PackedStringArray:
	return _priority_trace


func heat_display_state() -> Dictionary:
	var federal := Game.heat != null and Game.heat.federal_enabled
	return {
			"value": Game.heat.value if Game.heat != null else 0.0,
			"max": FEDERAL_HEAT_PRESENTATION_MAX if federal else Rates.HEAT_MAX,
			"policy": &"absolute_0_200" if federal else &"ordinary_0_100",
			"federal": federal,
	}


## The mode lines. Nothing is laid out per-mode: they stack, and a line with no text takes
## no room, so the block grows and shrinks with what is actually happening.
func _build_modes() -> void:
	_modes = VBoxContainer.new()
	_modes.name = "Modes"
	_modes.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_modes.offset_left = 26.0
	_modes.offset_right = -26.0
	_modes.offset_top = MODES_TOP
	_modes.offset_bottom = MODES_TOP + MODE_H * MODE_ROWS
	_modes.add_theme_constant_override("separation", 2)
	_modes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modes.z_index = 1
	add_child(_modes)
	_objective = PaperKit.type_label("OBJECTIVE  ·  KEEP THE BALL IN PLAY", &"caption",
			Presentation.theme.newsprint)
	_objective.name = "Objective"
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.clip_text = false
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_objective.z_index = 1
	_objective_backdrop = ColorRect.new()
	_objective_backdrop.name = "ObjectiveBackdrop"
	_objective_backdrop.color = Color(Presentation.theme.ink, 0.76)
	_objective_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_backdrop.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(_objective_backdrop)
	add_child(_objective)

	# The Commission goes first: while a fight is on, it is the only thing on the table.
	_boss = _add_mode(Presentation.theme.dirty)
	_meeting = _add_mode(Presentation.theme.brass)
	_collect = _add_mode(Presentation.theme.clean)
	_wire = _add_mode(Presentation.theme.newsprint.darkened(0.2))
	_casino = _add_mode(Presentation.theme.neon_rose)
	# M3. The endgame lines sit under the M2 ones, in the order they matter when several are
	# live at once: the Feds first (they are the whole Night), then the crown, then the job.
	_federal = _add_mode(Presentation.theme.police)
	_empire = _add_mode(Presentation.theme.brass.lightened(0.08))
	_heist = _add_mode(Presentation.theme.neon_teal)
	_docks = _add_mode(Presentation.theme.brass.darkened(0.10))
	_city = _add_mode(Presentation.theme.brass.lightened(0.18))
	_ritual = _add_mode(Presentation.theme.brass.lightened(0.15))


func _add_mode(color: Color) -> Label:
	var l := PaperKit.type_label("", &"caption", color)
	l.add_theme_font_size_override("font_size", 20)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.visible = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modes.add_child(l)
	return l


static func _set_mode(l: Label, text: String) -> void:
	if l == null:
		return
	if l.text != text:
		l.text = text
	l.visible = not text.is_empty()


func _add_label(at: Vector2, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var role: StringName = &"metadata"
	if size >= PaperKit.FONT_HUGE:
		role = &"hero"
	elif size >= PaperKit.FONT_BIG:
		role = &"primary_value"
	elif size >= PaperKit.FONT_BODY:
		role = &"body"
	var l := PaperKit.type_label("", role, color, align)
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.offset_left = at.x
	l.offset_right = -26.0
	l.offset_top = at.y
	l.offset_bottom = at.y + float(size) + 12.0
	add_child(l)
	return l


func refresh() -> void:
	_on_dirty(Game.wallet.dirty)
	_on_clean(Game.wallet.clean)
	_on_heat(Game.heat.value)
	_on_respect(Game.respect)
	_on_night(Game.night_no)
	_update_guy()
	_update_modes()


func _process(delta: float) -> void:
	if _combo_left > 0.0:
		_combo_left = maxf(_combo_left - delta, 0.0)
		_combo.modulate.a = clampf(_combo_left / COMBO_FLASH, 0.0, 1.0)
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		if _flash_left <= 0.0:
			_flash = ""
	_update_guy()
	_update_modes()


# --- the modes ----------------------------------------------------------------


## Four clocks and lights, drawn from the model every frame because three of them are
## counting down. Anything with nothing to say renders as an empty line and disappears.
func _update_modes() -> void:
	if _modes == null:
		return
	# Keep every producer live and model-backed, but give the player one readable objective. The
	# priority order is the deterministic ownership contract: a live boss owns the line before
	# the meeting, then collection, wire, casino, endgame, job, and the ritual fallback.
	var modes: Array[Dictionary] = [
		{"id": &"boss", "label": _boss, "text": _boss_text()},
		{"id": &"meeting", "label": _meeting, "text": _meeting_text()},
		{"id": &"collection", "label": _collect, "text": _collection_text()},
		{"id": &"wire", "label": _wire, "text": _wire_text()},
		{"id": &"casino", "label": _casino, "text": _casino_text()},
		{"id": &"federal", "label": _federal, "text": _federal_text()},
		{"id": &"empire", "label": _empire, "text": _empire_text()},
		{"id": &"heist", "label": _heist, "text": _heist_text()},
		{"id": &"docks", "label": _docks, "text": _docks_text()},
		{"id": &"city", "label": _city, "text": _city_text()},
		{"id": &"ritual", "label": _ritual, "text": _ritual_text()},
	]
	var objective_text := ""
	_priority_trace = PackedStringArray()
	_selected_objective_source = &"fallback"
	for mode: Dictionary in modes:
		var label := mode["label"] as Label
		var text := String(mode["text"])
		var source := StringName(mode["id"])
		_priority_trace.append("%s:%s" % [String(source), "active" if not text.is_empty() else "idle"])
		_set_mode(label, text)
		if objective_text.is_empty() and not text.is_empty():
			objective_text = _short_objective(text)
			_selected_objective_source = source
		# Producer labels remain a compatibility/debug surface but are not equal-weight rows.
		label.visible = false
	if objective_text.is_empty():
		objective_text = _job_objective()
		_priority_trace.append("job:%s" % ("active" if not objective_text.is_empty() else "idle"))
	_objective.text = "OBJECTIVE  ·  " + objective_text
	_objective.visible = true
	_objective.add_theme_font_size_override("font_size", 17 if _compact else 22)
	_objective.custom_minimum_size.y = 42.0 if _compact else 50.0
	_objective.clip_text = false
	_fit_objective()


func _short_objective(text: String) -> String:
	var parts := text.split("   ·   ")
	if parts.size() <= 2:
		return " ".join(text.split(" ", false))
	# Keep the name and the actionable counter/clock; long flavor stays in the source producer.
	return "%s  ·  %s" % [" ".join(String(parts[0]).split(" ", false)),
			" ".join(String(parts[1]).split(" ", false))]


func _fit_objective() -> void:
	if _objective == null:
		return
	var available := maxf(_objective_backdrop.size.x - 24.0, 120.0) \
			if _objective_backdrop != null else maxf(_logical_viewport.x - 72.0, 120.0)
	var preferred := 17 if _compact else 22
	var minimum := 12 if _compact else 15
	var font := _objective.get_theme_font(&"font")
	var px := preferred
	# Two lines are reserved by the objective band. Fit against that reservation without
	# ellipsizing; the copy remains complete and wraps at word boundaries.
	while px > minimum and font.get_string_size(_objective.text, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, px).x > available * 1.85:
		px -= 1
	_objective.add_theme_font_size_override("font_size", px)


func _job_objective() -> String:
	var active := Game.jobs.active_jobs()
	if active.is_empty():
		return "KEEP THE BALL IN PLAY"
	var job: Dictionary = active[0]
	var name := String(job.get("name", "TONIGHT'S WORK"))
	var description := String(job.get("desc", "KEEP THE BALL IN PLAY"))
	if description.is_empty():
		return name
	return "%s  ·  %s" % [name, description]


## The fight, when there is one: who, which phase, and what he is doing to you right now.
## Manny's collect rides the same line when nothing is fighting, because both are "something
## happened that you did not do with the flippers".
func _boss_text() -> String:
	var fight := Game.boss
	if fight != null and is_instance_valid(fight) and bool(fight.get("active")):
		var line := String(fight.call("phase_line")) if fight.has_method("phase_line") else ""
		return "%s   ·   PHASE %d/%d%s" % [String(fight.get("boss_name")),
				mini(int(fight.get("phase")), int(fight.get("phases"))),
				int(fight.get("phases")), "" if line.is_empty() else "   ·   " + line]
	return _flash


func _meeting_text() -> String:
	if Game.meeting.active:
		return "%s   ·   ALL DIRTY x%d   ·   BACK ROOM %s" \
				% ["FAMILY REUNION" if Game.meeting.is_reunion() else "FAMILY MEETING",
					int(Game.meeting.dirty_multiplier()),
					Game.meeting.jackpot_value(Game.stats.idle_rate_total()).text()]
	if Game.meeting.lit:
		return "BACK ROOM LIT   ·   FAMILY MEETING READY"
	var need := FamilyMeeting.JACKPOTS_TO_LIGHT - Game.meeting.jackpots_tonight
	if Game.casino.night_jackpots > 0 and need > 0:
		return "BACK ROOM   ·   %d MORE JACKPOT%s" % [need, "" if need == 1 else "S"]
	return ""


func _collection_text() -> String:
	if not Game.collection.active:
		return ""
	return "COLLECTION ROUND   ·   %d/3   ·   %0.1fs" \
			% [Game.collection.collected_count(), maxf(Game.collection.time_left, 0.0)]


func _wire_text() -> String:
	if Game.wire.draws <= 0 and Game.wire.time_left >= WireDraws.PERIOD - 0.05:
		return ""
	var ticket := 0
	var live := Game.night as NightController
	if live != null and is_instance_valid(live):
		ticket = posmod(int(TableAPI.call_if(live.table, "spinner_spins", [], 0)),
				WireDraws.NUMBERS)
	var drawn := "--" if Game.wire.last_number < 0 else "%02d" % Game.wire.last_number
	var line := "THE WIRE   ·   DREW %s   ·   YOUR TICKET %02d   ·   NEXT %ds" \
			% [drawn, ticket, int(ceilf(maxf(Game.wire.time_left, 0.0)))]
	# The Wiretap: the number arrives before the draw does, and the spinner is the bet slip.
	var early := Game.wire.early_number(Game.stats.flag(&"wiretap_wire"))
	if early >= 0:
		line += "   ·   WIRETAP SAYS %02d" % early
	return line


func _casino_text() -> String:
	var armed := Game.casino.armed_multiplier()
	if armed > 1.0:
		# The ladder rides the BET, not the payout (balance-sim ruling), and the HUD has to say
		# so — a player who reads "next payout" is being sold an edge he did not buy.
		return "HIGH ROLLER   ·   NEXT BET x%d" % int(armed)
	if Game.casino.loss_streak >= Casino.CasinoRules.COOLER_STREAK:
		return "THE COOLER GOT FIRED   ·   NEXT WIN PAYS MORE"
	return ""


# --- the endgame lines (M3) ---------------------------------------------------


## THE RICO RAID and the blue meter (docs/05 §9). During the wiretap phase this line is one
## of the redundancy channels the audio is deliberately not: it says the phase in words while
## the mix is being taken apart (docs/08 §6).
func _federal_text() -> String:
	var live := Game.night as NightController
	var raid: RicoRaid = null
	if live != null and is_instance_valid(live):
		raid = live.rico
	if raid != null and is_instance_valid(raid) and raid.active:
		var wire := "" if raid.wiretap_step <= 0 \
				else "   ·   WIRES CUT %d/%d" % [raid.wiretap_step, AudioDirector.RICO_STEPS]
		return "R I C O   ·   PHASE %d/%d %s   ·   %ds%s" % [raid.phase, RicoRaid.PHASES,
				raid.phase_line(), int(ceilf(maxf(raid.time_left, 0.0))), wire]
	if not Game.federal.enabled:
		return ""
	if Game.federal.rico_pending:
		return "FEDERAL %d   ·   THEY ARE AT THE DOOR" % int(round(Game.federal.meter_value()))
	if Game.federal.value <= 0.0:
		return ""
	var nights := Game.federal.nights_to_rico(Game.owned_node_count())
	var eta := "" if nights < 0 else "   ·   %d NIGHT%s" % [nights, "" if nights == 1 else "S"]
	return "FEDERAL %d/200%s" % [int(round(Game.federal.meter_value())), eta]


## EMPIRE MODE and the circuit that lights it (docs/02 §2 R7).
func _empire_text() -> String:
	if Game.empire.active:
		return "E M P I R E   ·   EVERYTHING x%d   ·   %ds" \
				% [int(EmpireMode.DIRTY_MULT), int(ceilf(maxf(Game.empire.time_left, 0.0)))]
	if Game.empire.leg <= 0:
		return ""
	return "CITY HALL CIRCUIT   ·   %d/%d   ·   NEXT: %s" % [Game.empire.leg,
			EmpireMode.LEGS.size(), String(Game.empire.next_leg()).to_upper()]


## The heist checklist: one beat at a time, which is how the crew is reading it too.
func _heist_text() -> String:
	var job := Game.heist
	if job == null or not job.active:
		return ""
	var blown := "" if job.blown <= 0 else "   ·   %d BLOWN" % job.blown
	return "%s   ·   %d/%d %s %d/%d   ·   %ds%s" % [job.target_name, job.beat_index + 1,
			job.beats().size(), String(job.beat().get("line", "")), job.beat_hits,
			int(job.beat().get("count", 1)), int(ceilf(maxf(job.time_left, 0.0))), blown]


## The smuggling window and the Sit-Down's freeze — the two things the Docks and the
## Penthouse do to a Night.
func _docks_text() -> String:
	if Game.sitdown.active:
		return "SIT-DOWN   ·   HEAT FROZEN   ·   %ds" \
				% int(ceilf(maxf(Game.sitdown.time_left, 0.0)))
	if not Game.smuggling.active:
		return ""
	var truck := "   ·   ON THE TRUCK x2" if Game.smuggling.hot else ""
	return "SHIPMENT   ·   %d/%d STACKS   ·   %ds%s" % [Game.smuggling.cleared_count(),
			SmugglingRun.STACKS, int(ceilf(maxf(Game.smuggling.time_left, 0.0))), truck]


## The campaign, the ballot and the term (docs/05 §8), plus the room that unlocks them.
func _city_text() -> String:
	if Game.elections.active:
		return "ELECTION NIGHT   ·   %d/%d VOTES   ·   %ds" % [Game.elections.votes,
				Elections.VOTES_TO_WIN, int(ceilf(maxf(Game.elections.time_left, 0.0)))]
	if Game.elections.in_office():
		return "CITY HALL   ·   %d NIGHT%s LEFT" % [Game.elections.term_left,
				"" if Game.elections.term_left == 1 else "S"]
	if Game.elections.unlocked:
		return "THE CAMPAIGN   ·   %d/%d DISTRICTS" \
				% [Game.elections.lit_count(), Elections.DISTRICTS.size()]
	if Game.chairs.claimed_count() > 0 and not Game.chairs.all_claimed():
		return "THE COMMISSION   ·   %d/%d CHAIRS" \
				% [Game.chairs.claimed_count(), CommissionChairs.CHAIRS]
	return ""


## The phone and the case (docs/05 §10). The phone wins the line while it is ringing, because
## it is the one with a clock on it — and it never says who is calling, which is the decision.
func _ritual_text() -> String:
	# THE RAT wins the line on a clue Night: three names, which of them are out, and whether
	# the top lanes are live as an accusation (docs/05 §7).
	if Game.rat.active:
		var frame := PackedStringArray()
		for i in Game.rat.suspects.size():
			var who := Game.rat.suspect_name(i)
			frame.append("[%s]" % who if Game.rat.is_cleared(i) else who.to_upper())
		var how := "NAME HIM ON THE TOP LANES" if Game.rat.can_accuse() \
				else "%d/%d CLUES" % [Game.rat.clues.size(), TheRat.CLUES_TO_ACCUSE]
		return "SOMETHING'S OFF   ·   %s   ·   %s" % [" ".join(frame), how]
	if Game.phone.ringing:
		return "THE PHONE   ·   ANSWER IT ON THE PAYPHONES   ·   %ds" \
				% int(ceilf(maxf(Game.phone.time_left, 0.0)))
	if Game.briefcases.boon_left > 0.0:
		return "THE CASE   ·   ALL DIRTY x%d   ·   %ds" % [
				int(Briefcases.BOON_DOUBLE_MULT), int(ceilf(Game.briefcases.boon_left))]
	var live := Game.night as NightController
	if live != null and is_instance_valid(live) \
			and bool(TableAPI.call_if(live.table, "briefcase_live", [], false)):
		return "A MAN WITH A BRIEFCASE IS WAITING"
	return ""


func _update_guy() -> void:
	if _guy == null:
		return
	var name := "NO GUY ON"
	var next := "WAITING FOR THE TABLE"
	if night_controller != null and is_instance_valid(night_controller) and night_controller.running:
		var guy := night_controller.current_guy()
		if not guy.is_empty():
			name = "GUY  " + String(guy["name"])
			next = "%d UP NEXT" % night_controller.guys_left()
	if name != _guy.text:
		_guy.text = name
	_fit_text_font(_guy, _guy.text, 17 if _compact else 27, 11 if _compact else 16)
	if _guy_meta != null and next != _guy_meta.text:
		_guy_meta.text = next


# --- model signals ------------------------------------------------------------


func _on_dirty(v: BigMoney) -> void:
	_dirty.text = "DIRTY  " + v.text()
	_fit_text_font(_dirty, _dirty.text, COMPACT_MONEY_FONT if _compact else PaperKit.FONT_BIG,
			15 if _compact else 24)


func _on_clean(v: BigMoney) -> void:
	_clean.text = "CLEAN  " + v.text()
	_fit_text_font(_clean, _clean.text, COMPACT_MONEY_FONT if _compact else PaperKit.FONT_BIG,
			15 if _compact else 24)


func _on_heat(v: float) -> void:
	if _heat != null:
		_heat.set_heat(v)


func _on_respect(total: int) -> void:
	var next := Game.respect_to_next_rank()
	_respect.text = "RESPECT %d" % total
	_respect_hint.text = ("%d TO R%d" % [next, Game.rank + 1]) if next > 0 else "MAX RANK"
	var threshold := Game.rank_threshold(Game.rank)
	var next_threshold := Game.rank_threshold(Game.rank + 1)
	var interval := maxi(next_threshold - threshold, 1)
	var progress := 1.0 if next <= 0 else clampf(float(total - threshold) / float(interval), 0.0, 1.0)
	_respect_meter.set_progress(progress)
	_fit_text_font(_respect, _respect.text, 17 if _compact else 28, 12 if _compact else 16)
	_fit_text_font(_respect_hint, _respect_hint.text, 14 if _compact else 20,
			11 if _compact else 14)


func _on_rank(_rank: int) -> void:
	_on_respect(Game.respect)
	_on_night(Game.night_no)


func _on_night(n: int) -> void:
	_night.text = "NIGHT %d   ·   %s" % [n, Game.rank_title()]
	_fit_text_font(_night, _night.text, 18 if _compact else 24, 13 if _compact else 17)


func _on_guy_changed(_guy: Dictionary) -> void:
	_update_guy()


## Manny walked a till while you were busy (`auto_collect_interval`).
func _on_auto_collected(id: StringName, amount: BigMoney) -> void:
	var shop := String(id).replace("storefront_", "").to_upper()
	_flash = "MANNY COLLECTED %s   ·   %s" % [shop, amount.text()]
	_flash_left = AUTO_COLLECT_FLASH


func _on_combo(count: int) -> void:
	if count < 2:
		_combo_left = 0.0
		_combo.modulate.a = 0.0
		return
	_combo.text = "x%d  CLEAN WORK" % count
	_combo_left = COMBO_FLASH
	_combo.modulate.a = 1.0


func _on_charge(power: float) -> void:
	if _charge != null:
		_charge.set_charge(power)


func _fit_text_font(label: Label, text: String, preferred: int, minimum: int) -> void:
	if label == null:
		return
	var available := maxf(label.size.x - 2.0, 1.0)
	var font := label.get_theme_font(&"font")
	var px := preferred
	while px > minimum and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x > available:
		px -= 1
	label.add_theme_font_size_override("font_size", px)


## The compact chrome gives the two information bands a shared baseline without owning any
## gameplay state. Values and labels remain separate controls above this decoration.
class HudChrome:
	extends Control

	var compact := false
	var margins := Vector4.ZERO
	var profile: Dictionary = {}

	func configure(is_compact: bool, safe_margins: Vector4, layout_profile: Dictionary) -> void:
		compact = is_compact
		margins = safe_margins
		profile = layout_profile
		queue_redraw()

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var inner_left := margins.x
		var inner_right := size.x - margins.z
		var divider_y := (margins.y + 48.0) if compact else (margins.y + 72.0)
		var brass := Presentation.theme.brass
		var newsprint := Presentation.theme.newsprint
		draw_line(Vector2(inner_left, margins.y + 1.0), Vector2(inner_right, margins.y + 1.0),
			Color(brass, 0.55), 2.0)
		draw_line(Vector2(inner_left, divider_y), Vector2(inner_right, divider_y),
			Color(brass, 0.28), 1.0)
		if compact:
			var safe_w := maxf(inner_right - inner_left, 1.0)
			for ratio: float in [0.20, 0.595, 0.78]:
				var x := inner_left + safe_w * ratio
				draw_line(Vector2(x, margins.y + 10.0), Vector2(x, divider_y - 9.0),
					Color(newsprint, 0.14), 1.0)
		else:
			for ratio: float in [0.20, 0.68, 0.75]:
				var x := inner_left + (inner_right - inner_left) * ratio
				draw_line(Vector2(x, margins.y + 16.0), Vector2(x, divider_y - 12.0),
					Color(newsprint, 0.14), 1.0)
		# A small mechanical marker separates this strip from the table; it is intentionally
		# neutral so Dirty/Clean/Heat/Police keep their semantic ownership.
		draw_circle(Vector2(inner_left, divider_y), 3.0, Color(brass, 0.72))
		draw_circle(Vector2(inner_right, divider_y), 3.0, Color(brass, 0.72))


## The Heat dial with band edges marked, labels, and a hatch warning so the warning survives
## grayscale and reduced flash (docs/03 §4).
class HeatBar:
	extends Control

	var value: float = 0.0
	var compact := false
	var federal := false

	func configure(is_compact: bool) -> void:
		compact = is_compact
		federal = _federal_stage_enabled()
		queue_redraw()

	func set_heat(v: float) -> void:
		var next_federal := _federal_stage_enabled()
		var changed_scale := next_federal != federal
		federal = next_federal
		var cap := FEDERAL_HEAT_PRESENTATION_MAX if federal else Rates.HEAT_MAX
		if not changed_scale and is_equal_approx(v, value):
			return
		value = clampf(v, 0.0, cap)
		queue_redraw()

	func _federal_stage_enabled() -> bool:
		return Game.heat != null and Game.heat.federal_enabled

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var metadata_type := Presentation.theme.typography_for(&"metadata")
		var font := metadata_type["font"] as Font
		var type_size := 15 if compact else 20
		var label_color := Presentation.theme.newsprint
		draw_string(font, Vector2(0.0, float(type_size)), "HEAT", HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, type_size, label_color)
		# Federal is deliberately absolute, not normalized: `/ 200` keeps the endpoint
		# readable while the model continues to own its independent 0..200 value.
		var cap := FEDERAL_HEAT_PRESENTATION_MAX if federal else Rates.HEAT_MAX
		var number := "%d / %d" % [int(round(value)), int(cap)]
		var number_width := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			 type_size).x
		draw_string(font, Vector2(size.x - number_width, float(type_size)), number,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, type_size, label_color)
		var meter_top := float(type_size + 5)
		var meter_height := maxf(size.y - meter_top - (9.0 if compact else 13.0), 8.0)
		var meter := Rect2(0.0, meter_top, size.x, meter_height)
		draw_rect(meter, Color(Presentation.theme.ink, 0.94), true)
		var fraction := clampf(value / cap, 0.0, 1.0)
		var band := Rates.band_for(value)
		var col := Presentation.theme.heat.darkened(0.30) if band == 0 else Presentation.theme.heat
		if federal and value >= Rates.RAID_THRESHOLD:
			col = Presentation.theme.police
		elif band >= 4:
			col = Presentation.theme.dirty
		var filled := Rect2(meter.position, Vector2(meter.size.x * fraction, meter.size.y))
		draw_rect(filled, col, true)
		if (band >= 2 or (federal and value >= Rates.RAID_THRESHOLD)) and filled.size.x > 4.0:
			var hatch_step := 11.0 if compact else 15.0
			var x := filled.position.x - filled.size.y
			while x < filled.end.x:
				draw_line(Vector2(maxf(x, filled.position.x), filled.end.y),
					Vector2(minf(x + filled.size.y, filled.end.x), filled.position.y),
					Color(Presentation.theme.newsprint, 0.44), 1.5)
				x += hatch_step
		var thresholds := PackedFloat64Array(Rates.BAND_THRESHOLDS)
		if federal:
			# Keep the ordinary raid boundary and the readable Federal endpoint on one dial.
			thresholds.append(FEDERAL_HEAT_PRESENTATION_MAX)
		for threshold: float in thresholds:
			var marker_x := meter.position.x + meter.size.x * threshold / cap
			draw_line(Vector2(marker_x, meter.position.y), Vector2(marker_x, meter.end.y),
				Color(Presentation.theme.newsprint, 0.78), 1.0)
			var marker := "%d" % int(threshold)
			var marker_width := font.get_string_size(marker, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				10).x
			if not compact or threshold == 90.0 or (federal and threshold >= Rates.RAID_THRESHOLD):
				draw_string(font, Vector2(clampf(marker_x - marker_width * 0.5, 0.0,
					size.x - marker_width), size.y - 1.0), marker, HORIZONTAL_ALIGNMENT_LEFT,
					-1.0, 10, Color(Presentation.theme.newsprint, 0.72))
		draw_rect(meter, Color(Presentation.theme.brass, 0.76), false, 2.0)


class RespectMeter:
	extends Control

	var progress := 0.0
	var compact := false

	func configure(is_compact: bool) -> void:
		compact = is_compact
		queue_redraw()

	func set_progress(next: float) -> void:
		progress = clampf(next, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var track := Rect2(0.0, 0.0, size.x, maxf(size.y, 5.0))
		draw_rect(track, Color(Presentation.theme.ink, 0.92), true)
		draw_rect(Rect2(track.position, Vector2(track.size.x * progress, track.size.y)),
			Presentation.theme.brass, true)
		draw_rect(track, Color(Presentation.theme.newsprint, 0.56), false, 1.0)
		var tick_x := track.size.x * 0.5
		draw_line(Vector2(tick_x, 0.0), Vector2(tick_x, track.size.y),
			Color(Presentation.theme.newsprint, 0.60), 1.0)


class PlungerLane:
	extends Control

	var value := 0.0
	var compact := false

	func configure(is_compact: bool) -> void:
		compact = is_compact
		queue_redraw()

	func set_charge(power: float) -> void:
		value = clampf(power, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var rail_width := 26.0 if compact else 38.0
		# Standard reserves transparent copy space to the left of the physical lane.
		# Keep the rail at the same right-anchored world position as the former 72px
		# control; compact remains centered in its shallow 44px control.
		var rail_center_x := size.x * 0.5 if compact else size.x - 36.0
		var rail := Rect2(rail_center_x - rail_width * 0.5, 24.0, rail_width,
			maxf(size.y - 54.0, 24.0))
		draw_rect(Rect2(rail.position - Vector2(8.0, 8.0), rail.size + Vector2(16.0, 16.0)),
			Color(Presentation.theme.ink, 0.74), true)
		draw_rect(rail, Color(Presentation.theme.ink, 0.95), true)
		var fill_height := rail.size.y * value
		if fill_height > 0.0:
			draw_rect(Rect2(rail.position + Vector2(0.0, rail.size.y - fill_height),
				Vector2(rail.size.x, fill_height)), Presentation.theme.brass, true)
		for detent: float in [0.35, 0.70, 1.0]:
			var y := rail.end.y - rail.size.y * detent
			draw_line(Vector2(rail.position.x - 10.0, y), Vector2(rail.end.x + 10.0, y),
				Color(Presentation.theme.newsprint, 0.88), 2.0)
			if not compact or detent < 1.0:
				var micro_type := Presentation.theme.typography_for(&"micro")
				draw_string(micro_type["font"] as Font, Vector2(rail.end.x + 14.0, y + 4.0),
					"MAX" if detent >= 1.0 else "%d" % int(detent * 100.0),
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13 if compact else 16,
					Color(Presentation.theme.newsprint, 0.74))
		draw_rect(rail, Color(Presentation.theme.brass, 0.90), false, 2.0)
		var micro_type := Presentation.theme.typography_for(&"micro")
		var font := micro_type["font"] as Font
		var pull := "PULL" if compact else "PULL  ·  LAUNCH"
		var pull_width := font.get_string_size(pull, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			14 if compact else 18).x
		draw_string(font, Vector2((size.x - pull_width) * 0.5, 15.0), pull,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14 if compact else 18,
			Color(Presentation.theme.newsprint, 0.88))
		var arrow_x := rail.get_center().x
		draw_line(Vector2(arrow_x, rail.end.y + 9.0), Vector2(arrow_x, rail.end.y + 19.0),
			Color(Presentation.theme.brass, 0.90), 2.0)
		draw_line(Vector2(arrow_x, rail.end.y + 19.0), Vector2(arrow_x - 5.0, rail.end.y + 13.0),
			Color(Presentation.theme.brass, 0.90), 2.0)
		draw_line(Vector2(arrow_x, rail.end.y + 19.0), Vector2(arrow_x + 5.0, rail.end.y + 13.0),
			Color(Presentation.theme.brass, 0.90), 2.0)


## The brass star next to the Respect count — drawn because the default font has no glyph.
class StarBadge:
	extends Control

	func _draw() -> void:
		var center := size * 0.5
		draw_circle(center, size.x * 0.48, Color(Presentation.theme.ink, 0.92))
		draw_arc(center, size.x * 0.46, 0.0, TAU, 20, Color(Presentation.theme.brass, 0.78), 1.5)
		PaperKit.draw_star(self, center, size.x * 0.34, Presentation.theme.brass)
