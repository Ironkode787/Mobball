extends Node
## Model-level adapter for the opt-in, on-device beta funnel. No network code lives here.

var store := TelemetryStore.new()
var _last_state: StringName = &""
var _first_launch_seen := false
var _first_earn_seen := false
var _night_active := false


func _ready() -> void:
	store.build = build_version()
	store.load()
	Events.session_booted.connect(_on_session_booted)
	Events.night_started.connect(_on_night_started)
	Events.night_ended.connect(_on_night_ended)
	Events.ball_launched.connect(_on_ball_launched)
	Events.dirty_earned.connect(_on_dirty_earned)
	Events.upgrade_purchased.connect(_on_upgrade_purchased)
	Events.raid_started.connect(func() -> void: store.record("raid_started"))
	Events.raid_ended.connect(func(survived: bool) -> void:
		store.record("raid_completed", {"survived": survived}))
	Game.state_changed.connect(_on_state_changed)


func set_enabled(enabled: bool) -> bool:
	var ok := store.set_consent(TelemetryStore.CONSENT_GRANTED if enabled \
			else TelemetryStore.CONSENT_DENIED)
	if ok and enabled:
		store.begin_session()
	return ok


func enabled() -> bool:
	return store.consent == TelemetryStore.CONSENT_GRANTED


func clear_data() -> bool:
	return store.clear_data()


func export_report() -> bool:
	return store.export_report()


func report_json() -> String:
	return store.report_json()


func event_count() -> int:
	return store.event_count()


static func build_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "development"))


func _on_session_booted() -> void:
	_last_state = &"attract"
	store.begin_session()


func _on_state_changed(state: StringName) -> void:
	if _last_state == &"attract" and state == &"roll_call":
		store.record("front_door_start")
	if state == &"roll_call":
		store.record("roll_call_viewed")
	elif state == &"ledger":
		store.record("ledger_viewed")
	_last_state = state


func _on_night_started(night_no: int) -> void:
	_night_active = true
	_first_launch_seen = false
	_first_earn_seen = false
	store.record("night_started", {"night_bucket": _night_bucket(night_no)})


func _on_ball_launched(_ball: Node2D, _power: float) -> void:
	if not _night_active or _first_launch_seen:
		return
	_first_launch_seen = true
	store.record("night_first_ball_launched")


func _on_dirty_earned(_amount: BigMoney, group: StringName) -> void:
	if not _night_active or _first_earn_seen or group == &"idle":
		return
	_first_earn_seen = true
	store.record("night_first_active_earn")


func _on_upgrade_purchased(_id: String, level: int) -> void:
	store.record("upgrade_purchased", {"level_bucket": "1" if level <= 1 else "2_plus"})


func _on_night_ended(summary: Dictionary) -> void:
	_night_active = false
	var raid := raid_outcome(summary)
	store.record("night_completed", {
		"night_bucket": _night_bucket(int(summary.get("night", 0))),
		"guys_lost": _small_bucket(int(summary.get("guys_lost", summary.get("drains", 0)))),
		"tilts": _small_bucket(int(summary.get("tilts", 0))),
		"jobs_done": _small_bucket(int(summary.get("jobs_done", 0))),
		"best_combo": _combo_bucket(int(summary.get("best_combo", 0))),
		"rank_bucket": "r%d" % clampi(int(summary.get("rank", 0)), 0, 7),
		"raid": raid,
		"rank_up": bool(summary.get("rank_up", false)),
	})


static func raid_outcome(summary: Dictionary) -> String:
	var rico := String(summary.get("rico", ""))
	if rico in ["survived", "lost"]:
		return rico
	var raid := String(summary.get("raid", ""))
	return raid if raid in ["survived", "lost"] else "none"


static func _night_bucket(value: int) -> String:
	if value <= 1:
		return "1"
	if value <= 3:
		return "2_3"
	if value <= 10:
		return "4_10"
	return "11_plus"


static func _small_bucket(value: int) -> String:
	return str(clampi(value, 0, 3)) if value < 4 else "4_plus"


static func _combo_bucket(value: int) -> String:
	if value <= 1:
		return "0_1"
	if value <= 4:
		return "2_4"
	return "5_plus"
