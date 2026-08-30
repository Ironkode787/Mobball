# Phase 5 — The Opening

Phase 5 turns the playable build into a closed-beta candidate without pretending that local
code can press buttons in Play Console. The repository now owns a privacy-light feedback loop,
a credential-gated release path, truthful store materials, save integrity, and repeatable
acceptance evidence. Upload, review, tester invitations, and physical-device soak results remain
operator actions.

## Closed-beta funnel

- Collection is off until the player explicitly allows it in House Rules.
- The queue stays on device; there is no SDK, device/install identifier, wall-clock timestamp,
  exact balance, player name, or automatic upload.
- Fixed events cover the front door, Roll Call, first launch, first active earning, Night
  completion, Ledger, upgrades, and Raids. Rich gameplay signal payloads are never serialized.
- Elapsed time is bucketed from a monotonic session clock and the queue is capped at 512 events.
- Players can copy/export a deterministic report, clear it, or turn collection off and clear it.
  Telemetry data is separate from both `save1.json` and `presentation.cfg`.

## Release boundary

`Android Beta` is a distinct arm64 AAB preset at version `0.5.0-beta.1` / code `5`, targeting
API 36. It excludes tests, simulations, debug HUD/table resources, tools, docs, release artwork,
and artifacts. The release builder:

- requires an external upload keystore, alias, password, and approved SHA-256 fingerprint;
- rejects the committed debug key and `androiddebugkey` alias;
- removes the expected output before export and honors the exporter exit code;
- verifies the AAB signature and actual Bundletool manifest values;
- rejects dirty and untracked source, bootstraps the matching Godot Gradle template, and pins
  Bundletool 1.18.3 by SHA-256; and
- emits a manifest containing version, source commit, target API, artifact hash, and signer hash.

The existing development APK remains a sideload path only. Its stale-artifact masking bug is
also fixed.

## Player trust and store readiness

- Career saves are now v3 and carry a SHA-256 integrity field. Tampered/damaged candidates
  salvage from rolling backups; v1/v2 saves remain readable and upgrade on their next save.
- `THE USUAL SUSPECTS` provides in-game engine, font, generated-art, and audio credits inside
  the same safe-area rules as House Rules.
- The store kit contains reviewed listing copy, screenshot briefs, privacy disclosure, a
  closed-beta playbook, device matrix, and a 1024×500 feature graphic.
- ImageGen created only the promotional background. Exact branding was overlaid with the
  repository's licensed Oswald font; no fake gameplay UI or generated lettering ships.

## Gates and honest remaining work

The local gate covers import, unit checks, boot, all simulations, release-preset policy, the
rounded/cutout device journey, and a clean package denylist once credentials produce the AAB.
The final ship command also generates and installs a universal APK from that AAB, launches it on
the selected Android device, and rejects fatal packaged-runtime errors.
Before inviting external testers, the operator must also complete the physical-device matrix,
30-minute thermal run, Play data-safety form, content rating, upload-key setup, and closed-track
rollout.

The Phase 4 draw-call baseline remains 194 against the 120 min-spec target. Cities 3–5 and Play
Games are also not present. Store copy therefore describes only the game that exists; none of
those debts are silently reclassified as complete.

## Verification

- Godot 4.5 import and 600-frame boot.
- 8,358 unit checks, zero failures.
- All 12 simulation scenes, including the v3 save/reload first-ten-minutes scenario.
- Static release probe for channel, Gradle/AAB policy, API 26–36 range, resource exclusions,
  and version agreement.
- Real 486×864 device journey with asymmetric insets and a rounded-corner guard, including the
  compact HUD, first-Night coach, beta telemetry touch target, and credits return control.
- Shell syntax validation and deterministic 1024×500 store-art generation.

No beta AAB was produced in this phase because the private upload key is deliberately not
committed. When that operator input and a release-test device are present, the ship gate installs
the matching ignored Gradle template, then inspects the actual bundle's signer, SDK manifest,
packed-resource denylist, and generated universal APK before it writes release evidence.
