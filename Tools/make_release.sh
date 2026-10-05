#!/bin/zsh
# Builds a Release copy of Camera Overlay and packages it as a drag-to-Applications
# DMG plus a zip in ./dist (git-ignored). Attach both files to a GitHub release.
# Run from the repository root:
#
#   Tools/make_release.sh
#
# Requires Xcode. Output: dist/CameraOverlay-<version>.dmg and .zip

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="CameraOverlay.xcodeproj"
SCHEME="CameraOverlay"
DERIVED="$PWD/build/release-dd"
STAGING="$PWD/build/dmg-staging"
MOUNT="$PWD/build/dmg-mount"
APP="$DERIVED/Build/Products/Release/CameraOverlay.app"
VOLUME_NAME="Camera Overlay"

echo "▸ Building Release…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED" build -quiet

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
echo "▸ Version $VERSION"

echo "▸ Verifying code signature…"
codesign --verify --strict --deep "$APP"

mkdir -p dist
rm -rf "$STAGING" "$MOUNT"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="$PWD/dist/CameraOverlay-$VERSION.dmg"
ZIP="$PWD/dist/CameraOverlay-$VERSION.zip"
rm -f "$DMG" "$ZIP"

# Preferred: let the system build the image from the folder. This needs access to
# /Volumes, which some sandboxed shells (e.g. Xcode's assistant) don't have; there it
# fails fast and we fall back below. (diskutil image create can hang in that case.)
make_dmg_simple() {
  hdiutil create -quiet -volname "$VOLUME_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" 2>/dev/null
}

# Fallback: build the filesystem in user space (no /Volumes needed), then mount it at a
# local path to strip the Finder metadata makehybrid adds (codesign --strict rejects it).
make_dmg_fallback() {
  local hybrid="$PWD/build/hybrid.dmg" rw="$PWD/build/rw.dmg"
  rm -f "$hybrid" "$rw"
  mkdir -p "$MOUNT"
  hdiutil makehybrid -quiet -hfs -hfs-volume-name "$VOLUME_NAME" -o "$hybrid" "$STAGING"
  hdiutil convert -quiet "$hybrid" -format UDRW -o "$rw"
  hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$MOUNT" "$rw"
  xattr -cr "$MOUNT/CameraOverlay.app"
  hdiutil detach -quiet "$MOUNT"
  hdiutil convert -quiet "$rw" -format UDZO -o "$DMG"
  rm -f "$hybrid" "$rw"
}

echo "▸ Creating $DMG…"
if ! make_dmg_simple || [ ! -f "$DMG" ]; then
  echo "  (system image tools unavailable here, using makehybrid)"
  make_dmg_fallback
fi

echo "▸ Verifying app inside the DMG…"
mkdir -p "$MOUNT"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
codesign --verify --strict --deep "$MOUNT/CameraOverlay.app"
hdiutil detach -quiet "$MOUNT"

echo "▸ Creating $ZIP…"
ditto -c -k --keepParent "$APP" "$ZIP"

rm -rf "$STAGING" "$MOUNT"
echo "✓ Done"
ls -lh dist
