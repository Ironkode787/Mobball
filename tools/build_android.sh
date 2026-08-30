#!/usr/bin/env bash
# Build the Android debug APK. One-time setup is idempotent; the export re-runs freely.
#
# Requirements this script installs/creates if missing:
#   * Godot 4.5 export templates → ~/.local/share/godot/export_templates/4.5.stable
#   * apksigner + zipalign + adb (Debian packages) symlinked into a minimal SDK layout
#     at ~/android-sdk (Godot only needs those three binaries for a non-gradle export)
#   * editor settings pointing Godot at all of the above
#
# Signing: every build must use the SAME key. Android identifies an app by package name +
# signing certificate, so a fresh key produces an APK that will not install over the last
# one -- the phone reports a signature mismatch and demands an uninstall, which wipes the
# save. The key therefore lives in the repo (tools/android/debug.keystore) instead of being
# generated per machine. It is a debug key for sideloading only; a store release needs its
# own key, kept private.
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

# Keystore resolution, first hit wins. The in-repo key is the normal path; the env vars are
# escape hatches for signing with a key you would rather not commit.
KEYSTORE=""
if [ -n "${KINGPIN_KEYSTORE:-}" ]; then
	[ -f "$KINGPIN_KEYSTORE" ] || { echo "KINGPIN_KEYSTORE set but not a file: $KINGPIN_KEYSTORE"; exit 1; }
	KEYSTORE="$KINGPIN_KEYSTORE"
elif [ -n "${KINGPIN_KEYSTORE_B64:-}" ]; then
	KEYSTORE="$HOME/.kingpin-keystore.jks"
	printf '%s' "$KINGPIN_KEYSTORE_B64" | base64 -d > "$KEYSTORE" \
		|| { echo "KINGPIN_KEYSTORE_B64 is not valid base64"; exit 1; }
elif [ -f tools/android/debug.keystore ]; then
	KEYSTORE="$PWD/tools/android/debug.keystore"
fi

# No key found is a hard stop. Generating one here would silently ship an APK that cannot
# install over the previous build.
if [ -z "$KEYSTORE" ]; then
	echo "No signing keystore found. Expected tools/android/debug.keystore in the repo," >&2
	echo "or \$KINGPIN_KEYSTORE / \$KINGPIN_KEYSTORE_B64 in the environment." >&2
	exit 1
fi
KEYSTORE_USER="${KINGPIN_KEYSTORE_USER:-androiddebugkey}"
KEYSTORE_PASS="${KINGPIN_KEYSTORE_PASS:-android}"

JAVA_HOME_DIR="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
mkdir -p ~/.config/godot
cat > ~/.config/godot/editor_settings-4.5.tres <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/java_sdk_path = "$JAVA_HOME_DIR"
export/android/android_sdk_path = "$SDK"
export/android/debug_keystore = "$KEYSTORE"
export/android/debug_keystore_user = "$KEYSTORE_USER"
export/android/debug_keystore_pass = "$KEYSTORE_PASS"
EOF

echo "== exporting =="
mkdir -p build
rm -f build/kingpin-debug.apk
set +e
"$GODOT" --headless --path . --export-debug "Android Development" build/kingpin-debug.apk \
	>build/android-debug-export.log 2>&1
EXPORT_RC=$?
set -e
if [ $EXPORT_RC -ne 0 ]; then
	tail -80 build/android-debug-export.log
	echo "EXPORT FAILED (rc=$EXPORT_RC)" >&2
	exit $EXPORT_RC
fi
grep -E "ERROR|error" build/android-debug-export.log | grep -v "icon" || true
[ -s build/kingpin-debug.apk ] || { echo "EXPORT FAILED"; exit 1; }
apksigner verify build/kingpin-debug.apk && echo "signature ok"

# Print the signing identity: if this fingerprint ever changes, the next APK will not
# install over the last one, and this line is the only warning you get.
echo "signed by $(keytool -list -v -keystore "$KEYSTORE" -storepass "$KEYSTORE_PASS" 2>/dev/null \
	| grep -m1 SHA256 | tr -d ' \t')"
ls -la build/kingpin-debug.apk
echo "DONE — sideload build/kingpin-debug.apk (enable 'install unknown apps' on the phone)"
