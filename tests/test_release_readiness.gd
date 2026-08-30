extends RefCounted


func run(t: TestCtx) -> void:
	var cfg := ConfigFile.new()
	t.eq(cfg.load("res://export_presets.cfg"), OK, "release preset is readable")
	var exclude := String(cfg.get_value("preset.1", "exclude_filter", ""))
	t.eq(String(cfg.get_value("preset.1", "name", "")), "Android Beta", "dedicated beta preset")
	t.ok(String(cfg.get_value("preset.1", "export_path", "")).ends_with(".aab"),
			"Play artifact is an AAB")
	for denied: String in ["tests/*", "game/sim/*", "debug_hud", "alley_debug", "release/*"]:
		t.ok(denied in exclude, "beta bundle excludes %s" % denied)
	t.eq(String(cfg.get_value("preset.1.options", "version/name", "")), Telemetry.build_version(),
			"runtime/report version matches Android version")
	t.eq(int(cfg.get_value("preset.1.options", "version/code", 0)),
			int(ProjectSettings.get_setting("application/config/version_code", 0)),
			"closed beta has a monotonic version code")
	t.ok(bool(cfg.get_value("preset.1.options", "gradle_build/use_gradle_build", false)),
			"beta uses Gradle so target SDK policy reaches the manifest")
	t.eq(String(cfg.get_value("preset.1.options", "custom_template/release", "")),
			"res://tools/.cache/android_release-4.5.apk",
			"beta uses the checksum-pinned Godot release template")
	t.eq(String(cfg.get_value("preset.1.options", "gradle_build/target_sdk", "")), "36",
			"beta targets the current Play API deadline")
	var builder := FileAccess.get_file_as_string("res://tools/build_beta.sh")
	t.ok("bundletool" in builder.to_lower(), "AAB metadata is inspected with Bundletool")
	t.ok("--untracked-files=all" in builder, "release gate rejects untracked source")
	t.ok("/manifest/@android:versionName" in builder, "artifact version is inspected")
	t.ok("android:debuggable" in builder, "artifact debuggable flag is inspected")
	t.ok(FileAccess.file_exists("res://tools/setup_android_release.sh"),
			"release toolchain has a pinned bootstrap")
	t.ok("godot-release-config" in FileAccess.get_file_as_string(
			"res://tools/setup_android_release.sh"),
			"release bootstrap isolates Godot's SDK and JDK settings")
	t.ok(FileAccess.file_exists("res://tools/probe_android_package.sh"),
			"ship gate has an installable-package probe")
	t.ok(FileAccess.file_exists("res://tools/test_release_scripts.sh"),
			"release shell gates have failure-injection checks")
	for path: String in ["res://release/STORE_LISTING.md", "res://release/PRIVACY.md",
			"res://release/CLOSED_BETA.md", "res://release/DEVICE_MATRIX.md",
			"res://release/store/feature_graphic.png"]:
		t.ok(FileAccess.file_exists(path), "%s exists" % path)
	t.ok("Godot Engine" in CreditsSheet.credits_text(), "in-game credits name the engine")
	t.ok("SIL Open Font License" in CreditsSheet.credits_text(), "in-game credits name font license")
	t.ok(ReleaseChannel.allow_development_hooks(true, false), "debug builds allow QA hooks")
	t.ok(not ReleaseChannel.allow_development_hooks(false, true), "beta releases ignore QA hooks")
