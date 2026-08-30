#!/usr/bin/env bash
# Build and run the installable universal APK represented by the release AAB.
set -euo pipefail
cd "$(dirname "$0")/.."

AAB="${1:?Usage: tools/probe_android_package.sh path/to/release.aab}"
BUNDLETOOL_JAR="${BUNDLETOOL_JAR:-$PWD/tools/.cache/bundletool-all-1.18.3.jar}"
PACKAGE_ID="com.mobball.kingpin"

for TOOL in adb java unzip mktemp; do
	command -v "$TOOL" >/dev/null || { echo "Missing packaged-probe tool: $TOOL" >&2; exit 1; }
done
[ -s "$AAB" ] || { echo "Release AAB not found: $AAB" >&2; exit 1; }
[ -f "$BUNDLETOOL_JAR" ] || { echo "Pinned Bundletool not found: $BUNDLETOOL_JAR" >&2; exit 1; }
: "${KINGPIN_RELEASE_KEYSTORE:?Set KINGPIN_RELEASE_KEYSTORE}"
: "${KINGPIN_RELEASE_ALIAS:?Set KINGPIN_RELEASE_ALIAS}"
: "${KINGPIN_RELEASE_PASSWORD:?Set KINGPIN_RELEASE_PASSWORD}"

PROBE_TMP="$(mktemp -d)"
cleanup() {
	case "$PROBE_TMP" in
		"${TMPDIR:-/tmp}"/*) rm -rf -- "$PROBE_TMP" ;;
	esac
}
trap cleanup EXIT
printf '%s' "$KINGPIN_RELEASE_PASSWORD" > "$PROBE_TMP/password"
chmod 600 "$PROBE_TMP/password"

java -jar "$BUNDLETOOL_JAR" build-apks \
	--bundle="$AAB" \
	--output="$PROBE_TMP/release.apks" \
	--mode=universal \
	--ks="$KINGPIN_RELEASE_KEYSTORE" \
	--ks-key-alias="$KINGPIN_RELEASE_ALIAS" \
	--ks-pass="file:$PROBE_TMP/password" \
	--key-pass="file:$PROBE_TMP/password" \
	--overwrite
unzip -p "$PROBE_TMP/release.apks" universal.apk > "$PROBE_TMP/universal.apk"
[ -s "$PROBE_TMP/universal.apk" ] || { echo "Bundletool produced no universal APK" >&2; exit 1; }

ADB=(adb)
if [ -n "${KINGPIN_DEVICE_SERIAL:-}" ]; then
	ADB+=( -s "$KINGPIN_DEVICE_SERIAL" )
fi
"${ADB[@]}" get-state | grep -Fx device >/dev/null || { echo "No ready Android release-test device" >&2; exit 1; }
"${ADB[@]}" install -r "$PROBE_TMP/universal.apk" >/dev/null
"${ADB[@]}" logcat -c
"${ADB[@]}" shell monkey -p "$PACKAGE_ID" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 8
PID="$("${ADB[@]}" shell pidof "$PACKAGE_ID" | tr -d '\r')"
[ -n "$PID" ] || { echo "Packaged beta did not remain running" >&2; exit 1; }
RUNTIME_LOG="$("${ADB[@]}" logcat -d --pid="$PID" -v brief)"
if printf '%s\n' "$RUNTIME_LOG" | grep -E 'FATAL EXCEPTION|SCRIPT ERROR|Parse Error' >/dev/null; then
	printf '%s\n' "$RUNTIME_LOG" | tail -80
	echo "Packaged beta emitted a fatal runtime error" >&2
	exit 1
fi

echo "PACKAGED ANDROID PROBE OK — pid $PID"
