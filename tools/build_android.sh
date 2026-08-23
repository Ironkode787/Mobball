#!/usr/bin/env bash
# Build the Android debug APK. One-time setup is idempotent; the export re-runs freely.
#
# Requirements this script installs/creates if missing:
#   * Godot 4.5 export templates → ~/.local/share/godot/export_templates/4.5.stable
#   * apksigner + zipalign + adb (Debian packages) symlinked into a minimal SDK layout
#     at ~/android-sdk (Godot only needs those three binaries for a non-gradle export)
#   * a debug keystore at ~/debug.keystore (androiddebugkey / android)
#   * editor settings pointing Godot at all of the above
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/workspace/tools/godot/godot}"
TPL_DIR="$HOME/.local/share/godot/export_templates/4.5.stable"
SDK="$HOME/android-sdk"

if [ ! -d "$TPL_DIR" ]; then
	echo "== fetching export templates (~900MB, once) =="
	mkdir -p "$(dirname "$TPL_DIR")"
	curl -sSL -o /tmp/templates.tpz \
		"https://github.com/godotengine/godot/releases/download/4.5-stable/Godot_v4.5-stable_export_templates.tpz"
	(cd /tmp && unzip -q -o templates.tpz && mv templates "$TPL_DIR" && rm templates.tpz)
fi

command -v apksigner >/dev/null || { apt-get update -qq && apt-get install -y -qq apksigner zipalign adb; }
mkdir -p "$SDK/build-tools/34.0.0" "$SDK/platform-tools"
ln -sf "$(command -v apksigner)" "$SDK/build-tools/34.0.0/apksigner"
ln -sf "$(command -v zipalign)" "$SDK/build-tools/34.0.0/zipalign"
ln -sf "$(command -v adb)" "$SDK/platform-tools/adb"

if [ ! -f "$HOME/debug.keystore" ]; then
	keytool -genkeypair -keystore "$HOME/debug.keystore" -alias androiddebugkey \
		-storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
		-dname "CN=Android Debug,O=Android,C=US"
fi

JAVA_HOME_DIR="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
mkdir -p ~/.config/godot
cat > ~/.config/godot/editor_settings-4.5.tres <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/java_sdk_path = "$JAVA_HOME_DIR"
export/android/android_sdk_path = "$SDK"
export/android/debug_keystore = "$HOME/debug.keystore"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOF

echo "== exporting =="
mkdir -p build
"$GODOT" --headless --path . --export-debug "Android" build/kingpin-debug.apk 2>&1 \
	| grep -E "ERROR|error" | grep -v "icon" || true
[ -s build/kingpin-debug.apk ] || { echo "EXPORT FAILED"; exit 1; }
apksigner verify build/kingpin-debug.apk && echo "signature ok"
ls -la build/kingpin-debug.apk
echo "DONE — sideload build/kingpin-debug.apk (enable 'install unknown apps' on the phone)"
