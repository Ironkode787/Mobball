# Closed-beta operating loop

## Entry gate

- Green import, unit, boot, simulation, release, and cutout-device probes.
- Signed AAB from the private upload identity; recorded artifact and signer hashes.
- No tests, simulations, debug HUD/table, docs, tools, or store art in the bundle.
- Physical smoke on minimum, middle, and flagship devices with gesture navigation enabled.
- Store listing, privacy URL, data-safety answers, content rating, and tester contact route ready.

## Operator setup

Use Godot 4.5 stable with its matching export templates, Java, Android SDK platform 36, `adb`,
and a connected release-test device. Set `GODOT`, `ANDROID_SDK_ROOT`,
`JAVA_HOME`, `GODOT_EXPORT_TEMPLATES_DIR`, `KINGPIN_RELEASE_KEYSTORE`,
`KINGPIN_RELEASE_ALIAS`, `KINGPIN_RELEASE_PASSWORD`, and the approved
`KINGPIN_RELEASE_SHA256`. `tools/setup_android_release.sh` verifies and extracts the exact
Godot 4.5 Android templates, creates isolated Godot editor settings from the declared SDK/JDK
environment, and downloads checksum-pinned Bundletool 1.18.3 into the ignored tool cache.

Run `bash tools/ship.sh`. The gate rejects a dirty or untracked source tree, inspects the actual
AAB manifest and signer, scans packaged resources, builds a universal APK with Bundletool, and
installs that APK on the connected device for a launch/error smoke test before declaring success.

## Debug builds

Sideload APKs are never committed (`build/` is ignored). Publish them as GitHub pre-release
assets with `bash tools/release_apk.sh <tag>`, which builds the "Android Development" preset,
tags HEAD and uploads the APK with its sha256.

## Cohorts

Run three deliberate rounds rather than one large ambiguous test:

1. 10 players: first 10 minutes, touch feel, dirty/clean comprehension, crashes.
2. 20 players: first three Nights, Ledger decisions, Raid comprehension, accessibility.
3. 30+ players: multi-session retention instinct, balance spread, thermal/device outliers.

Ask players to share the optional local beta report only after qualitative feedback. Never make
telemetry consent a condition of access.

## Funnel review

Review falloff in this order: front door → Roll Call → Night start → first launch → first active
earn → Night complete → Ledger view → upgrade. Segment only by declared build; the report has no
identifier or device cohort. Treat tiny samples as interview prompts, not statistical truth.

## Hotfix loop

1. Reproduce and write a failing deterministic test or device journey.
2. Change the smallest tuning/content/code surface; never patch a tester save manually.
3. Run the full gate and the relevant 1,000-player-day strict balance profile.
4. Increment Android version code for every uploaded artifact, even if the name stays beta.
5. Record source commit, artifact hash, signer hash, fixes, known issues, and rollback build.
6. Stage to internal testers before promoting the same artifact to closed beta.

Stop promotion for save loss, crash-on-boot, input obstruction, unreadable cutout UI, signing
identity drift, corrupted package contents, or a performance regression on minimum spec.
