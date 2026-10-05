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
DERIVED="build/release-dd"
STAGING="build/dmg-staging"
APP="$DERIVED/Build/Products/Release/CameraOverlay.app"

echo "▸ Building Release…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED" build -quiet

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
echo "▸ Version $VERSION"

echo "▸ Verifying code signature…"
codesign --verify --strict --deep "$APP"

mkdir -p dist
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="dist/CameraOverlay-$VERSION.dmg"
ZIP="dist/CameraOverlay-$VERSION.zip"

echo "▸ Creating $DMG…"
hdiutil create -quiet -volname "Camera Overlay" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

echo "▸ Creating $ZIP…"
ditto -c -k --keepParent "$APP" "$ZIP"

rm -rf "$STAGING"
echo "✓ Done"
ls -lh dist
