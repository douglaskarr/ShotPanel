#!/bin/bash
# Builds ShotPanel.app into ./build without opening the Xcode project.
# Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/ShotPanel.app"
VERSION="1.0.0"

build_arch() {
  local triple="$1-apple-macosx14.0"
  if [ -z "${SDKROOT:-}" ] && ! swift build -c "$CONFIG" --triple "$triple"; then
    local fallback
    fallback="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1 || true)"
    if [ -z "$fallback" ]; then
      fallback="$(ls -d /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1 || true)"
    fi
    if [ -z "$fallback" ]; then exit 1; fi
    echo "Retrying with $fallback" >&2
    export SDKROOT="$fallback"
    swift build -c "$CONFIG" --triple "$triple"
  fi
  cp "$(swift build -c "$CONFIG" --triple "$triple" --show-bin-path)/ShotPanel" "$OUT/ShotPanel-$1"
}

OUT="$(mktemp -d)"
build_arch arm64
build_arch x86_64
lipo -create "$OUT/ShotPanel-arm64" "$OUT/ShotPanel-x86_64" -output "$OUT/ShotPanel"
BIN="$OUT/ShotPanel"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ShotPanel"

WORK="$(mktemp -d)"
swift scripts/make-icon.swift "$WORK/icon.png"
ICONSET="$WORK/ShotPanel.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/ShotPanel.icns"
rm -rf "$WORK" "$OUT"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ShotPanel</string>
  <key>CFBundleDisplayName</key><string>ShotPanel</string>
  <key>CFBundleIdentifier</key><string>com.dknewmedia.ShotPanel</string>
  <key>CFBundleExecutable</key><string>ShotPanel</string>
  <key>CFBundleIconFile</key><string>ShotPanel</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
  <key>NSDesktopFolderUsageDescription</key>
  <string>ShotPanel watches the folder where macOS saves your screenshots so it can gather them into one panel.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP"
