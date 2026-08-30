extends RefCounted

const QUEUE := "user://test_beta_telemetry.json"
const CONSENT := "user://test_beta_telemetry.cfg"
const EXPORT := "user://test_beta_telemetry_export.json"


func run(t: TestCtx) -> void:
	_cleanup()
	var clock := {"now": 1000}
	var store := TelemetryStore.new(QUEUE, CONSENT, EXPORT,
			func() -> int: return int(clock["now"]))
	store.load()
	t.eq(store.consent, TelemetryStore.CONSENT_UNKNOWN, "beta telemetry defaults to unknown")
	t.ok(not store.record("night_started", {"night_bucket": "1"}),
			"unknown consent records nothing")
	t.ok(not FileAccess.file_exists(QUEUE), "unknown consent creates no queue")
	t.ok(store.set_consent(TelemetryStore.CONSENT_GRANTED), "explicit beta consent persists")
	t.ok(store.begin_session(), "granted consent begins a session")
	clock["now"] = int(clock["now"]) + 91000
	t.ok(store.record("night_started", {"night_bucket": "1", "player_name": "NOPE"}),
			"allowlisted funnel event records")
	var report := store.report()
	t.eq((report["events"] as Array).size(), 2, "session and Night events are queued")
	var event: Dictionary = report["events"][1]
	t.eq(int(event["elapsed_bucket_s"]), 90, "elapsed time is coarse and monotonic")
	t.ok(not (event["props"] as Dictionary).has("player_name"), "unknown properties are redacted")
	t.ok(store.export_report(), "report exports without clearing")
	t.eq(store.event_count(), 2, "export is non-destructive")
	t.ok(FileAccess.file_exists(EXPORT), "sanitized export exists")

	var loaded := TelemetryStore.new(QUEUE, CONSENT, EXPORT,
			func() -> int: return int(clock["now"]))
	loaded.load()
	t.eq(loaded.consent, TelemetryStore.CONSENT_GRANTED, "consent survives restart")
	t.eq(loaded.event_count(), 2, "queue survives restart")
	var poisoned := loaded.report()
	var raw: Dictionary = (poisoned["events"] as Array)[1]
	(raw["props"] as Dictionary)["player_name"] = "LEAK"
	(raw["props"] as Dictionary)["night_bucket"] = "Felix Exact Balance 999"
	var poison_file := FileAccess.open(QUEUE, FileAccess.WRITE)
	poison_file.store_string(JSON.stringify(poisoned))
	poison_file.close()
	var sanitized := TelemetryStore.new(QUEUE, CONSENT, EXPORT,
			func() -> int: return int(clock["now"]))
	sanitized.load()
	var sanitized_props: Dictionary = (sanitized.report()["events"] as Array)[1]["props"]
	t.ok(not sanitized_props.has("player_name") and not sanitized_props.has("night_bucket"),
			"loaded queues are re-sanitized before report or export")
	loaded = sanitized
	for i in TelemetryStore.MAX_EVENTS + 8:
		loaded.record("ledger_viewed")
	t.eq(loaded.event_count(), TelemetryStore.MAX_EVENTS, "queue is hard-capped")
	t.ok(loaded.set_consent(TelemetryStore.CONSENT_DENIED), "opt-out persists")
	t.ok(not FileAccess.file_exists(QUEUE) and not FileAccess.file_exists(EXPORT),
			"opt-out clears local beta data")
	var resurrect := FileAccess.open(QUEUE, FileAccess.WRITE)
	resurrect.store_string(JSON.stringify(poisoned))
	resurrect.close()
	var denied_restart := TelemetryStore.new(QUEUE, CONSENT, EXPORT)
	denied_restart.load()
	t.eq(denied_restart.event_count(), 0, "denied restart cannot resurrect a leftover queue")
	t.ok(not FileAccess.file_exists(QUEUE), "off state removes leftover queue material")

	var missing_dir := "user://telemetry_missing_parent"
	var failed_consent := missing_dir + "/consent.cfg"
	var failed_opt_out := TelemetryStore.new(QUEUE, failed_consent, EXPORT)
	failed_opt_out.consent = TelemetryStore.CONSENT_GRANTED
	t.ok(not failed_opt_out.set_consent(TelemetryStore.CONSENT_DENIED),
			"failed opt-out preference write is reported")
	t.ok(FileAccess.file_exists(failed_opt_out.denial_marker_path()),
			"failed opt-out leaves a durable denial marker")
	var failed_reenable := TelemetryStore.new(QUEUE, failed_consent, EXPORT)
	t.ok(not failed_reenable.set_consent(TelemetryStore.CONSENT_GRANTED),
			"failed re-enable is reported")
	t.ok(FileAccess.file_exists(failed_reenable.denial_marker_path()),
			"failed re-enable cannot remove the denial marker first")
	var failed_restart := TelemetryStore.new(QUEUE, failed_consent, EXPORT)
	failed_restart.load()
	t.eq(failed_restart.consent, TelemetryStore.CONSENT_DENIED,
			"restart stays denied after failed opt-out and re-enable")
	DirAccess.remove_absolute(failed_restart.denial_marker_path())

	var alternate_consent := "user://test_beta_marker_fallback.cfg"
	var failed_marker := TelemetryStore.new(missing_dir + "/queue.json", alternate_consent, EXPORT)
	t.ok(failed_marker.set_consent(TelemetryStore.CONSENT_DENIED),
			"config persists opt-out when denial marker cannot be created")
	var marker_restart := TelemetryStore.new(missing_dir + "/queue.json", alternate_consent, EXPORT)
	marker_restart.load()
	t.eq(marker_restart.consent, TelemetryStore.CONSENT_DENIED,
			"marker-write failure still restarts opted out")
	DirAccess.remove_absolute(alternate_consent)

	var sentinel := "user://test_beta_career_sentinel.json"
	var file := FileAccess.open(sentinel, FileAccess.WRITE)
	file.store_string("career")
	file.close()
	loaded.clear_data()
	t.eq(FileAccess.get_file_as_string(sentinel), "career", "telemetry clear never touches career data")
	t.ok(loaded.set_consent(TelemetryStore.CONSENT_GRANTED),
			"recovery fixture explicitly restores consent")
	var previous := QUEUE + ".previous"
	var prior := FileAccess.open(previous, FileAccess.WRITE)
	prior.store_string(JSON.stringify({"format": TelemetryStore.FORMAT,
			"schema_version": TelemetryStore.SCHEMA_VERSION, "events": []}))
	prior.close()
	var recovered := TelemetryStore.new(QUEUE, CONSENT, EXPORT)
	recovered.load()
	t.ok(FileAccess.file_exists(QUEUE), "interrupted replacement recovers its previous queue")
	t.eq(Telemetry.raid_outcome({"raid": "survived"}), "survived",
			"ordinary Raid outcome is normalized")
	t.eq(Telemetry.raid_outcome({"raid": "", "rico": "lost"}), "lost",
			"RICO outcome is normalized")
	DirAccess.remove_absolute(sentinel)
	_cleanup()


func _cleanup() -> void:
	for path: String in [QUEUE, CONSENT, EXPORT, QUEUE + ".tmp", EXPORT + ".tmp",
			QUEUE + ".previous", EXPORT + ".previous", QUEUE + ".denied",
			"user://test_beta_marker_fallback.cfg"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
