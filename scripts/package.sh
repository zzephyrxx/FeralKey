#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
./scripts/build.sh
VERSION=0.10.0
STAGE="$(mktemp -d "$PWD/build/release-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/FeralKey-$VERSION" build/releases
# Explicit source allowlist: never include evidence, user exports, credentials,
# local build caches, or the separately installed Codex executable.
# rsync applies these rules at every depth, including source ZIP checkouts
# without .git. The source directory allowlist alone does not exclude secrets.
/usr/bin/rsync -a --safe-links \
  --exclude='.git/' --exclude='build/' --exclude='evidence/' \
  --exclude='.DS_Store' --exclude='.env*' --exclude='*auth.json' \
  --exclude='*token*.json' --exclude='*.xcuserstate' \
  --exclude='feralkey-device-research*.json' \
  --exclude='.build/' --exclude='.swiftpm/' --exclude='.idea/' --exclude='.vscode/' \
  --exclude='*.pcap' --exclude='*.pcapng' --exclude='*.btsnoop' --exclude='*.har' \
  --exclude='*.p12' --exclude='*.p8' --exclude='*.pem' --exclude='*.key' \
  Sources Resources scripts tests docs .github LICENSE README.md THIRD_PARTY.md \
  CONTRIBUTING.md SECURITY.md CHANGELOG.md .gitignore .gitattributes FeralKey_logo.png "$STAGE/FeralKey-$VERSION/"
/usr/bin/ditto -c -k --keepParent --norsrc "$STAGE/FeralKey-$VERSION" "build/releases/FeralKey-$VERSION-source.zip"
/usr/bin/ditto -c -k --keepParent --norsrc "build/FeralKey.app" "build/releases/FeralKey-$VERSION-macOS-$(uname -m).zip"
cd build/releases
/usr/bin/shasum -a 256 "FeralKey-$VERSION-source.zip" "FeralKey-$VERSION-macOS-$(uname -m).zip" > SHA256SUMS.txt
printf 'Release artifacts created in build/releases\n'
