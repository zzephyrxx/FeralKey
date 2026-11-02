#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -swift-version 5 -module-cache-path /private/tmp/rk98-swift-cache Sources/BluetoothResearch.swift tests/BluetoothResearchTests.swift -o build/bluetooth-research-tests
./build/bluetooth-research-tests
swiftc -swift-version 5 -module-cache-path /private/tmp/rk98-swift-cache Sources/Protocol.swift tests/ProtocolTests.swift -o build/protocol-tests
./build/protocol-tests
swiftc -swift-version 5 -module-cache-path /private/tmp/rk98-swift-cache Sources/Protocol.swift Sources/Lighting.swift Sources/Quota.swift Sources/Discovery.swift tests/QuotaTests.swift -framework IOKit -o build/quota-tests
./build/quota-tests
swiftc -swift-version 5 -module-cache-path /private/tmp/rk98-swift-cache Sources/Protocol.swift Sources/Lighting.swift Sources/Quota.swift Sources/CodexClient.swift tests/CodexClientTests.swift -o build/codex-client-tests
./build/codex-client-tests
swiftc -swift-version 5 -module-cache-path /private/tmp/rk98-swift-cache Sources/Protocol.swift Sources/Lighting.swift Sources/Quota.swift Sources/CodexClient.swift Sources/Discovery.swift Sources/HID.swift Sources/Theme.swift Sources/Features.swift Sources/SystemAudio.swift Sources/SystemNotifications.swift Sources/BannerTest.swift Sources/LabModel.swift tests/ModelSafetyTests.swift -framework AppKit -framework SwiftUI -framework IOKit -framework AVFoundation -framework Carbon -framework UserNotifications -framework ApplicationServices -framework ScreenCaptureKit -framework CoreMedia -o build/model-safety-tests
./build/model-safety-tests
swiftc -swift-version 5 -module-cache-path /private/tmp/rk98-swift-cache Sources/Protocol.swift Sources/Lighting.swift Sources/Quota.swift Sources/Features.swift tests/FeatureTests.swift -o build/feature-tests
./build/feature-tests
