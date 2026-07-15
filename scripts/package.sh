#!/usr/bin/env bash
#
# package.sh — build a Release build of DeepFocusTracker and zip it for sharing.
#
# Output: dist/DeepFocusTracker-<version>.zip  (a ditto archive of the .app).
# See PACKAGING.md for the full distribution picture (signing, Gatekeeper, etc.).

set -euo pipefail

PROJECT="DeepFocusTracker.xcodeproj"
SCHEME="DeepFocusTracker"
APP_NAME="DeepFocusTracker"
CONFIG="Release"
DERIVED_DATA="DerivedData"
DIST_DIR="dist"

usage() {
  cat <<'EOF'
package.sh — build a Release DeepFocusTracker and zip it for sharing.

Usage:
  scripts/package.sh            Release build → dist/DeepFocusTracker-<version>.zip
  scripts/package.sh --install  also copy the app into /Applications
  scripts/package.sh --open     reveal the finished zip in Finder
  scripts/package.sh --help     show this help

The app is ad-hoc signed ("Sign to Run Locally"), so the zip runs cleanly on
THIS Mac. On another Mac an un-notarized app is blocked until approved once:
System Settings → Privacy & Security → "Open Anyway", or
  xattr -dr com.apple.quarantine /path/to/DeepFocusTracker.app
For friction-free sharing you need Developer ID signing + notarization —
see PACKAGING.md.
EOF
}

install_app=false
reveal=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) install_app=true ;;
    --open)    reveal=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "package.sh: unknown option '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# Run from the repo root regardless of where the script is invoked from.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "==> Building $SCHEME ($CONFIG)…"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA" \
  build

app_path="$DERIVED_DATA/Build/Products/$CONFIG/$APP_NAME.app"
[[ -d "$app_path" ]] || { echo "error: build succeeded but $app_path is missing" >&2; exit 1; }

# Name the zip after the app's marketing version so shared files are traceable.
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$app_path/Contents/Info.plist" 2>/dev/null || echo dev)"

mkdir -p "$DIST_DIR"
zip_path="$DIST_DIR/$APP_NAME-$version.zip"
rm -f "$zip_path"

echo "==> Zipping → $zip_path"
# ditto (not `zip`) preserves the bundle's symlinks/metadata so the .app isn't
# corrupted in transit; --keepParent keeps the .app folder inside the archive.
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

if $install_app; then
  echo "==> Installing → /Applications/$APP_NAME.app"
  rm -rf "/Applications/$APP_NAME.app"      # replace any older copy
  ditto "$app_path" "/Applications/$APP_NAME.app"
fi

echo
echo "Done (v$version)."
echo "  app: $app_path"
echo "  zip: $zip_path"
if $install_app; then echo "  installed: /Applications/$APP_NAME.app"; fi
echo
echo "Sharing note: on another Mac an un-notarized app is blocked until approved"
echo "once — System Settings → Privacy & Security → \"Open Anyway\", or:"
echo "  xattr -dr com.apple.quarantine /path/to/$APP_NAME.app"
echo "See PACKAGING.md for friction-free (Developer ID + notarized) distribution."

if $reveal; then open -R "$zip_path"; fi
