#!/usr/bin/env bash
# Publish a debug APK as a GitHub pre-release asset instead of committing it.
#
#   bash tools/release_apk.sh <tag> [apk]
#
# Builds the "Android Development" preset when no APK is given, tags the current HEAD if the
# tag does not exist yet, then creates (or updates) the release with the APK and its sha256
# attached. Needs the GitHub CLI (`gh auth login`) and, for the build, Godot with the Android
# export templates and SDK configured in the editor settings.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?usage: release_apk.sh <tag> [apk]}"
APK="${2:-build/kingpin-debug.apk}"
GODOT="${GODOT:-/workspace/tools/godot/godot}"

command -v gh >/dev/null || { echo "gh (GitHub CLI) is required" >&2; exit 1; }

if [ -z "${2:-}" ]; then
	mkdir -p build
	"$GODOT" --headless --path . --export-debug "Android Development" "$APK"
fi
[ -f "$APK" ] || { echo "APK not found: $APK" >&2; exit 1; }

sha256sum "$APK" > "$APK.sha256"
VERSION_NAME="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot | head -1)"

if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
	git tag -a "$TAG" -m "KINGPIN $VERSION_NAME"
fi
git push origin "$TAG"

NOTES="Debug sideload build of KINGPIN $VERSION_NAME (source $(git rev-parse --short HEAD)).
sha256: $(cut -d' ' -f1 "$APK.sha256")
Install with \`adb install -r $(basename "$APK")\`; uninstall a build signed with another key first."

if gh release view "$TAG" >/dev/null 2>&1; then
	gh release upload "$TAG" "$APK" "$APK.sha256" --clobber
else
	gh release create "$TAG" "$APK" "$APK.sha256" --prerelease --title "KINGPIN $VERSION_NAME" --notes "$NOTES"
fi
echo "RELEASE OK: $TAG"
