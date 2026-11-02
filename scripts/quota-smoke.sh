#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -swift-version 5 -module-cache-path /private/tmp/rk98-swift-cache Sources/Protocol.swift Sources/Lighting.swift Sources/Quota.swift Sources/CodexClient.swift scripts/QuotaSmoke.swift -o build/quota-smoke
./build/quota-smoke "$@"
