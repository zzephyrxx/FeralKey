#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -swift-version 5 -module-cache-path /private/tmp/rk98-swift-cache Sources/Protocol.swift Sources/Lighting.swift Sources/Quota.swift Sources/CodexClient.swift Sources/Discovery.swift Sources/HID.swift Sources/Theme.swift Sources/Features.swift Sources/SystemAudio.swift Sources/SystemNotifications.swift Sources/BannerTest.swift Sources/LabModel.swift tests/AutoRefreshTimerTests.swift -framework AppKit -framework SwiftUI -framework IOKit -framework AVFoundation -framework Carbon -framework UserNotifications -framework ApplicationServices -framework ScreenCaptureKit -framework CoreMedia -o build/auto-refresh-tests
./build/auto-refresh-tests
