extends SceneTree
## Static, credential-free half of the beta ship gate.


func _initialize() -> void:
	var failures := 0
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		printerr("RELEASE PROBE: cannot read export presets")
		quit(1)
		return
	var section := "preset.1"
	var options := "preset.1.options"
	var checks := {
		"beta preset": String(cfg.get_value(section, "name", "")) == "Android Beta",
		"AAB output": String(cfg.get_value(section, "export_path", "")).ends_with(".aab"),
		"release channel": String(cfg.get_value(section, "custom_features", "")) == "beta",
		"tests excluded": "tests/*" in String(cfg.get_value(section, "exclude_filter", "")),
		"sim excluded": "game/sim/*" in String(cfg.get_value(section, "exclude_filter", "")),
		"debug HUD excluded": "debug_hud" in String(cfg.get_value(section, "exclude_filter", "")),
		"bundle format": int(cfg.get_value(options, "gradle_build/export_format", 0)) == 1,
		"Gradle release": bool(cfg.get_value(options, "gradle_build/use_gradle_build", false)),
		"Android 8 minimum": String(cfg.get_value(options, "gradle_build/min_sdk", "")) == "26",
		"API 36 target": String(cfg.get_value(options, "gradle_build/target_sdk", "")) == "36",
		"version name": String(cfg.get_value(options, "version/name", "")) == String(
				ProjectSettings.get_setting("application/config/version", "")),
		"version code": int(cfg.get_value(options, "version/code", 0)) == int(
				ProjectSettings.get_setting("application/config/version_code", 0)),
		"no network permission": (cfg.get_value(options, "permissions/custom_permissions", []) as Array).is_empty(),
	}
	for label: String in checks:
		if not bool(checks[label]):
			printerr("FAIL: ", label)
			failures += 1
	var forbidden := ["tests/", "game/sim/", "debug_hud", "alley_debug"]
	print("RELEASE PROBE: %s — denylist=%s" % ["OK" if failures == 0 else "%d FAILURES" % failures,
			forbidden])
	quit(0 if failures == 0 else 1)
