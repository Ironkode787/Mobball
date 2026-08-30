#!/usr/bin/env bash
# Credential-gated Google Play beta AAB. There is intentionally no debug-key fallback.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/workspace/tools/godot/godot}"
BUNDLETOOL_JAR="${BUNDLETOOL_JAR:-$PWD/tools/.cache/bundletool-all-1.18.3.jar}"
: "${JAVA_HOME:?Set JAVA_HOME to OpenJDK 17}"
export PATH="$JAVA_HOME/bin:$PATH"
export XDG_CONFIG_HOME="$PWD/tools/.cache/godot-release-config/xdg"
export APPDATA="$PWD/tools/.cache/godot-release-config/appdata"
VERSION_NAME="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot | head -1)"
VERSION_CODE="$(sed -n 's/^config\/version_code=//p' project.godot | head -1)"
[ -n "$VERSION_NAME" ] && [ -n "$VERSION_CODE" ] || {
	echo "Missing canonical application/config version in project.godot" >&2
	exit 1
}
OUT="build/release/kingpin-$VERSION_NAME.aab"
LOG="build/release/android-beta-export.log"

[ -x "$GODOT" ] || { echo "Godot executable not found: $GODOT" >&2; exit 1; }
for TOOL in java keytool jarsigner unzip sha256sum git; do
	command -v "$TOOL" >/dev/null || { echo "Missing release tool: $TOOL" >&2; exit 1; }
done
bash tools/setup_android_release.sh >/dev/null
[ -f "$BUNDLETOOL_JAR" ] || { echo "Pinned Bundletool not found: $BUNDLETOOL_JAR" >&2; exit 1; }

preset_value() {
	awk -v wanted="[$1]" -v key="$2" '
		{sub(/\r$/, "")}
		$0 == wanted { inside = 1; next }
		/^\[/ { inside = 0 }
		inside && index($0, key "=") == 1 {
			value = substr($0, length(key) + 2)
			gsub(/^"|"$/, "", value)
			print value
			exit
		}' export_presets.cfg
}

[ "$(preset_value preset.1 name)" = "Android Beta" ] || { echo "Missing Android Beta preset" >&2; exit 1; }
[ "$(preset_value preset.1.options version/name)" = "$VERSION_NAME" ] || { echo "Preset version name differs from project.godot" >&2; exit 1; }
[ "$(preset_value preset.1.options version/code)" = "$VERSION_CODE" ] || { echo "Preset version code differs from project.godot" >&2; exit 1; }
[ "$(preset_value preset.1.options package/unique_name)" = "com.mobball.kingpin" ] || { echo "Unexpected beta package ID" >&2; exit 1; }
[ "$(preset_value preset.1.options custom_template/release)" = "res://tools/.cache/android_release-4.5.apk" ] || { echo "Beta preset is not using the pinned release template" >&2; exit 1; }
[ "$(preset_value preset.1.options gradle_build/export_format)" = "1" ] || { echo "Beta preset is not an AAB export" >&2; exit 1; }
[ "$(preset_value preset.1.options gradle_build/use_gradle_build)" = "true" ] || { echo "Beta preset must use Gradle" >&2; exit 1; }
[ "$(preset_value preset.1.options gradle_build/min_sdk)" = "26" ] || { echo "Beta preset min SDK must be 26" >&2; exit 1; }
[ "$(preset_value preset.1.options gradle_build/target_sdk)" = "36" ] || { echo "Beta preset target SDK must be 36" >&2; exit 1; }

DIRTY="$(git status --porcelain=v1 --untracked-files=all | grep -v '^ M build/kingpin-debug.apk$' || true)"
[ -z "$DIRTY" ] || {
	echo "Release source tree has uncommitted changes:" >&2
	echo "$DIRTY" >&2
	exit 1
}

: "${KINGPIN_RELEASE_KEYSTORE:?Set KINGPIN_RELEASE_KEYSTORE to the private upload keystore}"
: "${KINGPIN_RELEASE_ALIAS:?Set KINGPIN_RELEASE_ALIAS to the upload-key alias}"
: "${KINGPIN_RELEASE_PASSWORD:?Set KINGPIN_RELEASE_PASSWORD without committing it}"
: "${KINGPIN_RELEASE_SHA256:?Set KINGPIN_RELEASE_SHA256 to the approved certificate fingerprint}"

[ -f "$KINGPIN_RELEASE_KEYSTORE" ] || { echo "Release keystore is not a file" >&2; exit 1; }
case "$(basename "$KINGPIN_RELEASE_KEYSTORE"):$KINGPIN_RELEASE_ALIAS" in
	debug.keystore:*|*:androiddebugkey)
		echo "Refusing the development signing identity for a beta release" >&2
		exit 1
		;;
esac

ACTUAL_SHA256="$(keytool -list -v -keystore "$KINGPIN_RELEASE_KEYSTORE" \
	-storepass "$KINGPIN_RELEASE_PASSWORD" -alias "$KINGPIN_RELEASE_ALIAS" 2>/dev/null \
	| awk -F'SHA256: ' '/SHA256:/{print $2; exit}' | tr -d '[:space:]')"
EXPECTED_SHA256="$(printf '%s' "$KINGPIN_RELEASE_SHA256" | tr -d '[:space:]')"
[ -n "$ACTUAL_SHA256" ] && [ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || {
	echo "Release certificate fingerprint mismatch" >&2
	exit 1
}

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KINGPIN_RELEASE_KEYSTORE"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$KINGPIN_RELEASE_ALIAS"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$KINGPIN_RELEASE_PASSWORD"

mkdir -p build/release
rm -f "$OUT" build/release/manifest.txt build/release/manifest.tmp
set +e
"$GODOT" --headless --path . --export-release "Android Beta" "$OUT" >"$LOG" 2>&1
EXPORT_RC=$?
set -e
if [ $EXPORT_RC -ne 0 ]; then
	tail -100 "$LOG"
	echo "BETA EXPORT FAILED (rc=$EXPORT_RC)" >&2
	exit $EXPORT_RC
fi
[ -s "$OUT" ] || { echo "Beta export produced no current artifact" >&2; exit 1; }
jarsigner -verify "$OUT" >/dev/null || { echo "AAB signature verification failed" >&2; exit 1; }

JAR_CERT="$(keytool -printcert -jarfile "$OUT" 2>/dev/null)"
AAB_SIGNER_SHA256="$(printf '%s\n' "$JAR_CERT" | awk -F'SHA256: ' '/SHA256:/{print $2; exit}' | tr -d '[:space:]')"
AAB_SIGNER_OWNER="$(printf '%s\n' "$JAR_CERT" | awk -F'Owner: ' '/Owner:/{print $2; exit}')"
[ "$AAB_SIGNER_SHA256" = "$ACTUAL_SHA256" ] || {
	echo "AAB signer differs from the approved upload key" >&2
	exit 1
}
case "$AAB_SIGNER_OWNER" in
	*"CN=Android Debug"*) echo "Refusing Android Debug certificate" >&2; exit 1 ;;
esac

bundle_manifest_value() {
	java -jar "$BUNDLETOOL_JAR" dump manifest --bundle="$OUT" --module=base --xpath="$1" | tr -d '\r\n'
}

AAB_MANIFEST="$(java -jar "$BUNDLETOOL_JAR" dump manifest --bundle="$OUT" --module=base)"
ACTUAL_PACKAGE="$(bundle_manifest_value '/manifest/@package')"
ACTUAL_VERSION_NAME="$(bundle_manifest_value '/manifest/@android:versionName')"
ACTUAL_VERSION_CODE="$(bundle_manifest_value '/manifest/@android:versionCode')"
ACTUAL_MIN_SDK="$(bundle_manifest_value '/manifest/uses-sdk/@android:minSdkVersion')"
ACTUAL_TARGET_SDK="$(bundle_manifest_value '/manifest/uses-sdk/@android:targetSdkVersion')"
[ "$ACTUAL_PACKAGE" = "com.mobball.kingpin" ] || { echo "AAB package is $ACTUAL_PACKAGE" >&2; exit 1; }
[ "$ACTUAL_VERSION_NAME" = "$VERSION_NAME" ] || { echo "AAB version name is $ACTUAL_VERSION_NAME" >&2; exit 1; }
[ "$ACTUAL_VERSION_CODE" = "$VERSION_CODE" ] || { echo "AAB version code is $ACTUAL_VERSION_CODE" >&2; exit 1; }
[ "$ACTUAL_MIN_SDK" = "26" ] || { echo "AAB min SDK is $ACTUAL_MIN_SDK, expected 26" >&2; exit 1; }
[ "$ACTUAL_TARGET_SDK" = "36" ] || { echo "AAB target SDK is $ACTUAL_TARGET_SDK, expected 36" >&2; exit 1; }
if printf '%s\n' "$AAB_MANIFEST" | grep -E 'android:debuggable="true"|debuggable: true' >/dev/null; then
	echo "AAB application is debuggable" >&2
	exit 1
fi

INVENTORY="$(unzip -Z1 "$OUT")"
if printf '%s\n' "$INVENTORY" | grep -Eiq \
	'(^|/)(tests|tools|docs|specs|release|game/sim)/|debug_hud|alley_debug'; then
	echo "AAB archive inventory contains development content" >&2
	exit 1
fi
if unzip -p "$OUT" 2>/dev/null | grep -aEiq \
	'res://(tests|tools|docs|specs|release|game/sim)/|res://game/ui/debug_hud|res://game/table/segments/alley_debug'; then
	echo "AAB packed resources contain development content" >&2
	exit 1
fi

COMMIT="$(git rev-parse HEAD)"
ARTIFACT_HASH="$(sha256sum "$OUT" | awk '{print $1}')"
cat > build/release/manifest.tmp <<EOF
product=KINGPIN
channel=closed-beta
version_name=$VERSION_NAME
version_code=$VERSION_CODE
min_sdk=$ACTUAL_MIN_SDK
target_sdk=$ACTUAL_TARGET_SDK
package_id=$ACTUAL_PACKAGE
source_commit=$COMMIT
artifact=$(basename "$OUT")
artifact_sha256=$ARTIFACT_HASH
signer_sha256=$AAB_SIGNER_SHA256
godot=$($GODOT --version | head -1)
java=$(java -version 2>&1 | head -1)
EOF
mv build/release/manifest.tmp build/release/manifest.txt
echo "BETA AAB OK — $OUT"
