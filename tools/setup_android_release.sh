#!/usr/bin/env bash
# Reproducible Android release-tool bootstrap. Generated/downloaded files stay ignored.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/workspace/tools/godot/godot}"
BUNDLETOOL_VERSION="1.18.3"
BUNDLETOOL_SHA256="a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29"
BUNDLETOOL_JAR="${BUNDLETOOL_JAR:-$PWD/tools/.cache/bundletool-all-$BUNDLETOOL_VERSION.jar}"
BUNDLETOOL_URL="https://github.com/google/bundletool/releases/download/$BUNDLETOOL_VERSION/bundletool-all-$BUNDLETOOL_VERSION.jar"
ANDROID_SOURCE_SHA256="04dc31f3096c8ae9c3364cc82d805c487a04fff8188d13461f422f5b68a2c452"
ANDROID_RELEASE_SHA256="939369b01a6e5c17e8b372dbc05a68eada6f989b0f2138ee7dafa844e0c86a7b"
TEMPLATE_DIR="${GODOT_EXPORT_TEMPLATES_DIR:?Set GODOT_EXPORT_TEMPLATES_DIR to the official Godot 4.5.stable templates directory}"
ANDROID_SOURCE_ZIP="$TEMPLATE_DIR/android_source.zip"
ANDROID_RELEASE_APK="$TEMPLATE_DIR/android_release.apk"
PINNED_RELEASE_APK="$PWD/tools/.cache/android_release-4.5.apk"
GODOT_RELEASE_CONFIG="$PWD/tools/.cache/godot-release-config"
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
: "${JAVA_HOME:?Set JAVA_HOME to OpenJDK 17}"
: "${SDK_ROOT:?Set ANDROID_SDK_ROOT to the Android SDK used by Godot}"

JAVA_BIN="$JAVA_HOME/bin/java"
[ -x "$JAVA_BIN" ] || JAVA_BIN="$JAVA_HOME/bin/java.exe"
[ -x "$JAVA_BIN" ] || { echo "OpenJDK executable not found under JAVA_HOME" >&2; exit 1; }
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"
export XDG_CONFIG_HOME="$GODOT_RELEASE_CONFIG/xdg"
export APPDATA="$GODOT_RELEASE_CONFIG/appdata"

[ -x "$GODOT" ] || { echo "Godot executable not found: $GODOT" >&2; exit 1; }
GODOT_VERSION="$($GODOT --version | head -1)"
case "$GODOT_VERSION" in
	4.5.stable*) ;;
	*) echo "Release toolchain requires Godot 4.5.stable, got: $GODOT_VERSION" >&2; exit 1 ;;
esac

for TOOL in sha256sum curl unzip; do
	command -v "$TOOL" >/dev/null || { echo "Missing release setup tool: $TOOL" >&2; exit 1; }
done
"$JAVA_BIN" -version 2>&1 | head -1 | grep -E 'version "17\.' >/dev/null || {
	echo "Release toolchain requires OpenJDK 17" >&2
	exit 1
}

for TEMPLATE in "$ANDROID_SOURCE_ZIP" "$ANDROID_RELEASE_APK"; do
	[ -f "$TEMPLATE" ] || { echo "Missing official Godot Android template: $TEMPLATE" >&2; exit 1; }
done
[ "$(sha256sum "$ANDROID_SOURCE_ZIP" | awk '{print $1}')" = "$ANDROID_SOURCE_SHA256" ] || {
	echo "Godot android_source.zip is not the pinned 4.5.stable template" >&2
	exit 1
}
[ "$(sha256sum "$ANDROID_RELEASE_APK" | awk '{print $1}')" = "$ANDROID_RELEASE_SHA256" ] || {
	echo "Godot android_release.apk is not the pinned 4.5.stable template" >&2
	exit 1
}

if [ ! -f "$BUNDLETOOL_JAR" ]; then
	mkdir -p "$(dirname "$BUNDLETOOL_JAR")"
	TMP_JAR="$BUNDLETOOL_JAR.partial"
	rm -f "$TMP_JAR"
	curl --fail --location --proto '=https' --tlsv1.2 "$BUNDLETOOL_URL" --output "$TMP_JAR"
	DOWNLOADED_SHA256="$(sha256sum "$TMP_JAR" | awk '{print $1}')"
	[ "$DOWNLOADED_SHA256" = "$BUNDLETOOL_SHA256" ] || {
		rm -f "$TMP_JAR"
		echo "Bundletool checksum mismatch" >&2
		exit 1
	}
	mv "$TMP_JAR" "$BUNDLETOOL_JAR"
fi

ACTUAL_BUNDLETOOL_SHA256="$(sha256sum "$BUNDLETOOL_JAR" | awk '{print $1}')"
[ "$ACTUAL_BUNDLETOOL_SHA256" = "$BUNDLETOOL_SHA256" ] || {
	echo "Bundletool is not the pinned $BUNDLETOOL_VERSION artifact" >&2
	exit 1
}
"$JAVA_BIN" -jar "$BUNDLETOOL_JAR" version | grep -Fx "$BUNDLETOOL_VERSION" >/dev/null || {
	echo "Bundletool version verification failed" >&2
	exit 1
}

BUILD_DIR="$PWD/android/build"
case "$BUILD_DIR" in
	"$PWD/android/build") ;;
	*) echo "Unsafe Android build-template path" >&2; exit 1 ;;
esac
rm -rf -- "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$(dirname "$PINNED_RELEASE_APK")"
unzip -q "$ANDROID_SOURCE_ZIP" -d "$BUILD_DIR"
cp "$ANDROID_RELEASE_APK" "$PINNED_RELEASE_APK"
for REQUIRED in android/build/AndroidManifest.xml android/build/build.gradle android/build/gradlew; do
	[ -f "$REQUIRED" ] || { echo "Incomplete Godot Android build template: $REQUIRED" >&2; exit 1; }
done
[ "$(sha256sum "$PINNED_RELEASE_APK" | awk '{print $1}')" = "$ANDROID_RELEASE_SHA256" ] || {
	echo "Pinned release APK copy failed integrity verification" >&2
	exit 1
}

[ -f "$SDK_ROOT/platforms/android-36/android.jar" ] || {
	echo "Android SDK platform 36 is not installed under $SDK_ROOT" >&2
	exit 1
}
[ -f "$SDK_ROOT/build-tools/35.0.0/aapt2" ] \
		|| [ -f "$SDK_ROOT/build-tools/35.0.0/aapt2.exe" ] || {
	echo "Android SDK build-tools 35.0.0 are not installed under $SDK_ROOT" >&2
	exit 1
}
[ -f "$SDK_ROOT/platform-tools/adb" ] || [ -f "$SDK_ROOT/platform-tools/adb.exe" ] || {
	echo "Android SDK platform-tools are not installed under $SDK_ROOT" >&2
	exit 1
}

case "$GODOT_RELEASE_CONFIG" in
	"$PWD/tools/.cache/godot-release-config") ;;
	*) echo "Unsafe Godot release-config path" >&2; exit 1 ;;
esac
rm -rf -- "$GODOT_RELEASE_CONFIG"
mkdir -p "$XDG_CONFIG_HOME" "$APPDATA"
set +e
CONFIG_OUT="$("$GODOT" --headless --editor --path . --quit-after 1 2>&1)"
CONFIG_RC=$?
set -e
if [ $CONFIG_RC -ne 0 ] || printf '%s\n' "$CONFIG_OUT" \
		| grep -E 'SCRIPT ERROR|Parse Error|ERROR: Failed' >/dev/null; then
	printf '%s\n' "$CONFIG_OUT" | tail -80
	echo "Godot isolated Android editor setup failed (rc=$CONFIG_RC)" >&2
	exit 1
fi
EDITOR_SETTINGS="$(find "$GODOT_RELEASE_CONFIG" -type f -name 'editor_settings-4.5.tres' -print -quit)"
[ -n "$EDITOR_SETTINGS" ] || { echo "Godot did not create isolated editor settings" >&2; exit 1; }
grep -F 'export/android/java_sdk_path = ' "$EDITOR_SETTINGS" >/dev/null || {
	echo "Godot editor settings contain no Java SDK path" >&2
	exit 1
}
grep -F 'export/android/android_sdk_path = ' "$EDITOR_SETTINGS" >/dev/null || {
	echo "Godot editor settings contain no Android SDK path" >&2
	exit 1
}

echo "ANDROID RELEASE TOOLCHAIN OK"
echo "BUNDLETOOL_JAR=$BUNDLETOOL_JAR"
