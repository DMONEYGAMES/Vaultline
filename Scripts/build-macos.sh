#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v swiftc >/dev/null 2>&1 || { echo "Swift compiler not found. Install Xcode Command Line Tools with: xcode-select --install"; exit 1; }
APP="$ROOT/Build/Vaultline.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/Build"

# Use the exact same artwork as the browser extension for the macOS app icon.
ICON_SOURCE="$ROOT/Extension/icons/icon128.png"
ICONSET="$ROOT/Build/Vaultline.iconset"
if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Extension icon not found: $ICON_SOURCE"
  exit 1
fi
command -v sips >/dev/null 2>&1 || { echo "sips is required to prepare the macOS app icon."; exit 1; }
command -v iconutil >/dev/null 2>&1 || { echo "iconutil is required to build the macOS app icon."; exit 1; }
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
make_icon() {
  local size="$1" filename="$2"
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/$filename" >/dev/null
}
make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Vaultline.icns"
rm -rf "$ICONSET"

swiftc -parse-as-library \
  "$ROOT/App/Sources/Vaultline/main.swift" \
  -o "$APP/Contents/MacOS/Vaultline" \
  -framework SwiftUI -framework AppKit -framework LocalAuthentication -framework Security

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Vaultline</string>
<key>CFBundleIdentifier</key><string>com.vaultline.desktop</string>
<key>CFBundleName</key><string>Vaultline</string>
<key>CFBundleDisplayName</key><string>Vaultline Desktop</string>
<key>CFBundleIconFile</key><string>Vaultline.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1000</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSFaceIDUsageDescription</key><string>Vaultline uses Mac authentication to approve access to saved logins.</string>
</dict></plist>
PLIST

swiftc "$ROOT/NativeHost/main.swift" -o "$ROOT/Build/vaultline-native-host" -framework LocalAuthentication -framework Security
chmod 755 "$ROOT/Build/vaultline-native-host" "$APP/Contents/MacOS/Vaultline"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP/Contents/Info.plist" >/dev/null
test -s "$APP/Contents/Resources/Vaultline.icns"

echo "Built $APP and $ROOT/Build/vaultline-native-host"
echo "Next: load Extension/ in Chrome, copy its ID to Docs/extension_id.txt, then run Scripts/install-native-host.sh."
