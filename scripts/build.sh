#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
FINAL_APP="${1:-$PWD/build/FeralKey.app}"
mkdir -p "${FINAL_APP:h}"
STAGE="$(mktemp -d "$PWD/build/app-stage.XXXXXX")"
APP="$STAGE/FeralKey.app"
cleanup() {
  # If installation of the new bundle failed, recover the last good bundle.
  if [[ ! -e "$FINAL_APP" && -d "$STAGE/previous.app" ]]; then
    if ! mv "$STAGE/previous.app" "$FINAL_APP"; then
      print -u2 "Could not restore previous app; preserved at $STAGE/previous.app"
      return 1
    fi
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -module-cache-path /private/tmp/rk98-swift-cache \
  -target "$(uname -m)-apple-macos13.0" \
  Sources/Protocol.swift Sources/Lighting.swift Sources/Features.swift Sources/SystemAudio.swift Sources/SystemNotifications.swift Sources/BannerTest.swift Sources/Quota.swift Sources/CodexClient.swift Sources/Discovery.swift Sources/HID.swift Sources/Theme.swift Sources/LabModel.swift Sources/QuotaViews.swift Sources/FeatureViews.swift Sources/LightingViews.swift Sources/ConnectionViews.swift Sources/Main.swift \
  -o "$APP/Contents/MacOS/FeralKey" \
  -framework UserNotifications -framework ApplicationServices -framework ScreenCaptureKit -framework CoreMedia -framework SwiftUI -framework AppKit -framework IOKit -framework AVFoundation -framework Carbon
# Explicit runtime resource allowlist. Never glob a contributor's local JSON.
cp Resources/rk98-layout.json Resources/keycodes.json "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Resources/SolidGlass-LICENSE.txt "$APP/Contents/Resources/"
cp FeralKey_logo.png "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/Docs"
cp docs/KEYBOARD-GUIDE.md docs/CODEX-QUOTA.md docs/TESTING.md docs/PERMISSIONS.md docs/COMPATIBILITY.md docs/USER-GUIDE.md "$APP/Contents/Resources/Docs/"
mkdir -p "$APP/Contents/Resources/Docs/history"
cp docs/history/FEATURES-*.md "$APP/Contents/Resources/Docs/history/"
mkdir -p "$APP/Contents/Resources/Docs/research"
cp docs/research/BLUETOOTH-RK98.md docs/research/RECEIVER-25A7-FA70.md "$APP/Contents/Resources/Docs/research/"
cp THIRD_PARTY.md "$APP/Contents/Resources/"
if [[ ! -f Resources/AppIcon.icns || scripts/MakeIcon.swift -nt Resources/AppIcon.icns || FeralKey_logo.png -nt Resources/AppIcon.icns ]]; then
  swift -module-cache-path /private/tmp/rk98-swift-cache scripts/MakeIcon.swift FeralKey_logo.png "$STAGE/FeralKey.iconset"
  iconutil -c icns "$STAGE/FeralKey.iconset" -o "$STAGE/AppIcon.icns"
  cp "$STAGE/AppIcon.icns" Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FeralKey</string>
<key>CFBundleIdentifier</key><string>local.zephyr.rk98lab</string>
<key>CFBundleName</key><string>FeralKey</string>
<key>CFBundleDisplayName</key><string>FeralKey</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.10.0</string>
<key>CFBundleVersion</key><string>10</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>FeralKey 仅分析系统播放音量以驱动音乐律动，不保存画面或声音，也不采集麦克风。</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleURLTypes</key><array><dict>
<key>CFBundleURLName</key><string>FeralKey actions</string>
<key>CFBundleURLSchemes</key><array><string>feralkey</string><string>rk98lab</string></array>
</dict></array>
</dict></plist>
PLIST
codesign --force --sign - --identifier local.zephyr.rk98lab "$APP"
codesign --verify --deep --strict "$APP"
# No mutation of the installed bundle occurs before build/sign/verify succeed.
if [[ -e "$FINAL_APP" ]]; then mv "$FINAL_APP" "$STAGE/previous.app"; fi
mv "$APP" "$FINAL_APP"
printf 'Built: %s\n' "$FINAL_APP"
