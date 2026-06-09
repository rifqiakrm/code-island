#!/bin/bash
# Build Code Island.app bundle, generate app icon, and package as DMG.
# Requires: swift, create-dmg (brew install create-dmg), sips, iconutil
set -e

VERSION="${1:-0.6.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Building release binary (v$VERSION)"
swift build -c release

echo "==> Creating app icon"
rm -rf build/AppIcon.iconset
mkdir -p build/AppIcon.iconset
SRC=design/logo.png
for sz in 16 32 64 128 256 512; do
  sips -z $sz $sz "$SRC" --out "build/AppIcon.iconset/icon_${sz}x${sz}.png" >/dev/null
done
for sz in 16 32 128 256 512; do
  dbl=$((sz * 2))
  sips -z $dbl $dbl "$SRC" --out "build/AppIcon.iconset/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

echo "==> Assembling app bundle"
APP="build/Code Island.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp .build/release/CodeIsland "$APP/Contents/MacOS/Code Island"
cp .build/release/CodeIslandBridge "$APP/Contents/Helpers/CodeIslandBridge"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Copy CLI provider icons into the app bundle so the notch can render them
if [ -d Resources/cli-icons ]; then
  cp -R Resources/cli-icons "$APP/Contents/Resources/cli-icons"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Code Island</string>
    <key>CFBundleIdentifier</key>
    <string>dev.codeisland.macos</string>
    <key>CFBundleName</key>
    <string>Code Island</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

echo "==> Building DMG"
DMG="build/Code-Island-${VERSION}.dmg"
rm -f "$DMG"
create-dmg \
  --volname "Code Island" \
  --volicon "build/AppIcon.icns" \
  --background "design/dmg-background.png" \
  --window-pos 200 120 \
  --window-size 660 425 \
  --icon-size 120 \
  --icon "Code Island.app" 170 205 \
  --app-drop-link 490 205 \
  --hide-extension "Code Island.app" \
  --no-internet-enable \
  "$DMG" \
  "$APP"

echo "==> Done: $DMG"
