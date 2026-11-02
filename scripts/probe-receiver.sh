#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/receiver-probe-cache
swiftc -swift-version 5 -module-cache-path "$PWD/build/receiver-probe-cache" Sources/Discovery.swift scripts/ReceiverProbe.swift -framework IOKit -o build/receiver-probe
exec build/receiver-probe "$@"
