#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
APP="$PWD/build/FeralKeyBluetoothProbe.app"
mkdir -p "$APP/Contents/MacOS" build/bluetooth-probe-cache evidence/bluetooth-rk98
if [[ ! -x build/bluetooth-hid-metadata || scripts/BluetoothHIDMetadata.swift -nt build/bluetooth-hid-metadata || Sources/BluetoothResearch.swift -nt build/bluetooth-hid-metadata ]]; then
  cp scripts/BluetoothHIDMetadata.swift build/bluetooth-probe-cache/main.swift
  swiftc -swift-version 5 -module-cache-path "$PWD/build/bluetooth-probe-cache" Sources/BluetoothResearch.swift build/bluetooth-probe-cache/main.swift -framework IOKit -o build/bluetooth-hid-metadata
fi
if [[ ! -x "$APP/Contents/MacOS/FeralKeyBluetoothProbe" || Sources/BluetoothResearch.swift -nt "$APP/Contents/MacOS/FeralKeyBluetoothProbe" || scripts/BluetoothProbe.swift -nt "$APP/Contents/MacOS/FeralKeyBluetoothProbe" || "$0" -nt "$APP/Contents/MacOS/FeralKeyBluetoothProbe" ]]; then
  swiftc -swift-version 5 -O -module-cache-path "$PWD/build/bluetooth-probe-cache" Sources/BluetoothResearch.swift scripts/BluetoothProbe.swift -framework CoreBluetooth -o "$APP/Contents/MacOS/FeralKeyBluetoothProbe"
  cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FeralKeyBluetoothProbe</string>
<key>CFBundleIdentifier</key><string>local.zephyr.feralkey-bluetooth-probe</string>
<key>CFBundleName</key><string>FeralKey 蓝牙诊断</string>
<key>CFBundleDisplayName</key><string>FeralKey 蓝牙诊断</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>仅读取已连接 RK98 的蓝牙服务、设备信息、电量与报告描述符，研究灯光控制是否可用；不写入灯光、固件，不读取按键内容。</string>
</dict></plist>
PLIST
  codesign --force --sign - --identifier local.zephyr.feralkey-bluetooth-probe "$APP"
fi
codesign --verify --deep --strict "$APP"
if [[ "${1:-}" == "--build-only" ]]; then exit 0; fi
if [[ "$#" -ne 0 ]]; then print -u2 '用法：scripts/probe-bluetooth.sh [--build-only]'; exit 2; fi
./build/bluetooth-hid-metadata > evidence/bluetooth-rk98/hid-metadata.json
open -W -g -n "$APP" --args --output "$PWD/evidence/bluetooth-rk98/gatt-services.json"
